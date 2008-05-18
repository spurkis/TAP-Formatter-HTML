=head1 NAME

TAP::Formatter::HTML - TAP Test Harness output delegate for html output

=head1 SYNOPSIS

 use TAP::Harness;

 my @tests = glob( 't/*.t' );
 my $harness = TAP::Harness->new({ formatter_class => 'TAP::Formatter::HTML',
                                   merge => 1 });
 $harness->runtests( @tests );
 # prints HTML to STDOUT by default

 # or if you don't want STDERR merged in:
 my $harness = TAP::Harness->new({ formatter_class => 'TAP::Formatter::HTML' });

 # to use a custom formatter:
 my $fmt = TAP::Formatter::HTML->new;
 $fmt->css_uris([])->inline_css( $my_css )
     ->js_uris(['http://mysite.com/jquery.js', 'http://mysite.com/custom.js'])
     ->inline_js( '$(div.summary).hide()' );

 my $harness = TAP::Harness->new({ formatter => $fmt, merge => 1 });

 # you can use your own customized templates too:
 $fmt->template('custom.tt2')
     ->template_processor( Template->new )
     ->force_inline_css(0);

=cut

package TAP::Formatter::HTML;

use strict;
use warnings;

use URI;
use Template;
use POSIX qw( ceil );
use File::Temp qw( tempfile tempdir );
use File::Spec::Functions qw( catdir catfile file_name_is_absolute rel2abs );

use TAP::Formatter::HTML::Session;

# DEBUG:
#use Data::Dumper 'Dumper';

use base qw( TAP::Base );
use accessors qw( verbosity stdout escape_output tests session_class sessions
		  template_processor template html
		  css_uris js_uris inline_css inline_js abs_file_paths force_inline_css );

use constant default_session_class => 'TAP::Formatter::HTML::Session';
use constant default_template      => 'TAP/Formatter/HTML/default_report.tt2';
use constant default_js_uris       => ['file:TAP/Formatter/HTML/jquery-1.2.3.pack.js'];
use constant default_css_uris      => ['file:TAP/Formatter/HTML/default_report.css'];
use constant default_template_processor =>
  Template->new(
		COMPILE_DIR  => catdir( tempdir(), 'TAP-Formatter-HTML' ),
		COMPILE_EXT  => '.ttc',
		INCLUDE_PATH => join(':', @INC),
	       );

use constant severity_map => {
			      ''          => 0,
			      'very-low'  => 1,
			      'low'       => 2,
			      'med'       => 3,
			      'high'      => 4,
			      'very-high' => 5,
			      0 => '',
			      1 => 'very-low',
			      2 => 'low',
			      3 => 'med',
			      4 => 'high',
			      5 => 'very-high',
			     };

our $VERSION = '0.01';

sub _initialize {
    my ($self, $args) = @_;

    $args ||= {};
    $self->SUPER::_initialize($args);
    $self->verbosity( 0 )
         ->stdout( \*STDOUT )
	 ->escape_output( 0 )
         ->abs_file_paths( 1 )
         ->abs_file_paths( 1 )
         ->force_inline_css( 1 )
         ->session_class( $self->default_session_class )
         ->template_processor( $self->default_template_processor )
         ->template( $self->default_template )
         ->js_uris( $self->default_js_uris )
         ->css_uris( $self->default_css_uris )
         ->inline_js( '' )
	 ->inline_css( '' );

    # Laziness...
    # trust the user knows what they're doing with the args:
    foreach my $key (keys %$args) {
	$self->$key( $args->{$key} ) if ($self->can( $key ));
    }

    return $self;
}

sub verbose {
    my $self = shift;
    # emulate a classic accessor for compat w/TAP::Formatter::Console:
    if (@_) { $self->verbosity(1) }
    return $self->verbosity >= 1;
}
sub quiet {
    my $self = shift;
    # emulate a classic accessor for compat w/TAP::Formatter::Console:
    if (@_) { $self->verbosity(-1) }
    return $self->verbosity <= -1;
}
sub really_quiet {
    my $self = shift;
    # emulate a classic accessor for compat w/TAP::Formatter::Console:
    if (@_) { $self->verbosity(-2) }
    return $self->verbosity <= -2;
}
sub silent {
    my $self = shift;
    # emulate a classic accessor for compat w/TAP::Formatter::Console:
    if (@_) { $self->verbosity(-3) }
    return $self->verbosity <= -3;
}

# Called by Test::Harness before any test output is generated.
sub prepare {
    my ($self, @tests) = @_;
    # warn ref($self) . "->prepare called with args:\n" . Dumper( \@tests );
    $self->info( 'running ', scalar @tests, ' tests' );
    $self->sessions([])->tests( [@tests] );
}

# Called to create a new test session. A test session looks like this:
#
#    my $session = $formatter->open_test( $test, $parser );
#    while ( defined( my $result = $parser->next ) ) {
#        $session->result($result);
#        exit 1 if $result->is_bailout;
#    }
#    $session->close_test;
sub open_test {
    my ($self, $test, $parser) = @_;
    #warn ref($self) . "->open_test called with args: " . Dumper( [$test, $parser] );
    my $session = $self->session_class->new({ test => $test,
					      parser => $parser,
					      formatter => $self });
    push @{ $self->sessions }, $session;
    return $session;
}

# $str = $harness->summary( $aggregate );
#
# C<summary> produces the summary report after all tests are run.  The argument is
# an aggregate.
sub summary {
    my ($self, $aggregate) = @_;
    #warn ref($self) . "->summary called with args: " . Dumper( [$aggregate] );

    # farmed out to make sub-classing easy:
    my $report = $self->prepare_report( $aggregate );
    $self->generate_report( $report );

    $self->_output( $self->html );

    return $self;
}

sub generate_report {
    my ($self, $r) = @_;

    $self->check_uris;
    $self->slurp_css if $self->force_inline_css;

    my $params = {
		  report => $r,
		  js_uris  => $self->js_uris,
		  css_uris => $self->css_uris,
		  incline_js  => $self->inline_js,
		  inline_css => $self->inline_css,
		  formatter => { class => ref( $self ),
				 version => $self->VERSION },
		 };

    my $html = '';
    $self->template_processor->process( $self->template, $params, \$html )
      || die $self->template_processor->error;

    $self->html( \$html );
}

# convert all uris to URI objs
# check file uris (if relative & not found, try & find them in @INC)
sub check_uris {
    my ($self) = @_;

    foreach my $uri_list ($self->js_uris, $self->css_uris) {
	# take them out of the list to verify, push them back on later
	my @uris = splice( @$uri_list, 0, scalar @$uri_list );
	foreach my $uri (@uris) {
	    $uri = URI->new( $uri );
	    if ($uri->scheme && $uri->scheme eq 'file') {
		my $path = $uri->path;
		unless (file_name_is_absolute($path)) {
		    my $new_path;
		    if (-e $path) {
			$new_path = rel2abs( $path ) if ($self->abs_file_paths);
		    } else {
			$new_path = $self->find_in_INC( $path );
		    }
		    $uri->path( $new_path ) if ($new_path);
		}
	    }
	    push @$uri_list, $uri;
	}
    }

    return $self;
}

sub prepare_report {
    my ($self, $a) = @_;

    my $r = {
	     tests => [],
	     start_time => '?',
	     end_time => '?',
	     elapsed_time => $a->elapsed_timestr,
	    };


    # add aggregate test info:
    for my $key (qw(
		    total
		    has_errors
		    has_problems
		    failed
		    parse_errors
		    passed
		    skipped
		    todo
		    todo_passed
		    wait
		    exit
		   )) {
	$r->{$key} = $a->$key;
    }

    # do some other handy calcs:
    $r->{actual_passed} = $r->{passed} + $r->{todo_passed};
    if ($r->{total}) {
	$r->{percent_passed} = sprintf('%.1f', $r->{actual_passed} / $r->{total} * 100);
    } else {
	$r->{percent_passed} = 0;
    }

    # estimate # files (# sessions could be different?):
    $r->{num_files} = scalar @{ $self->sessions };

    # add test results:
    my $total_time = 0;
    foreach my $s (@{ $self->sessions }) {
	my $sr = $s->as_report;
	push @{$r->{tests}}, $sr;
	$total_time += $sr->{elapsed_time} || 0;
    }
    $r->{total_time} = $total_time;

    # estimate total severity:
    my $smap = $self->severity_map;
    my $severity = 0;
    $severity += $smap->{$_->{severity} || ''} for @{$r->{tests}};
    my $avg_severity = ceil($severity / scalar( @{$r->{tests}} ));
    $r->{severity} = $smap->{$avg_severity};

    # TODO: coverage?

    return $r;
}

# adapted from Test::TAP::HTMLMatrix
# always return abs file paths if $self->abs_file_paths is on
sub find_in_INC {
    my ($self, $file) = @_;

    foreach my $path (grep { not ref } @INC) {
	my $target = catfile($path, $file);
	if (-e $target) {
	    $target = rel2abs($target) if $self->abs_file_paths;
	    return $target;
	}
    }

    # non-fatal
    $self->log("Warning: couldn't find $file in \@INC");
    return;
}

# adapted from Test::TAP::HTMLMatrix
# slurp all 'file' uris, if possible
# note: doesn't remove them from the css_uris list, just in case...
sub slurp_css {
    my ($self) = shift;
    $self->info("slurping css files inline");

    my $inline_css = $self->inline_css || '';
    foreach my $uri (@{ $self->css_uris }) {
	my $scheme = $uri->scheme;
	if ($scheme && $scheme eq 'file') {
	    my $path = $uri->path;
	    if (-e $path) {
		if (open my $fh, $path) {
		    local $/ = undef;
		    $inline_css .= <$fh>;
		} else {
		    $self->log("Warning: couldn't open $path: $!");
		}
	    } else {
		$self->log("Warning: couldn't read $path: file does not exist!");
	    }
	} else {
	    $self->log("Warning: can't include $uri inline: not a file uri");
	}
    }

    $self->inline_css( $inline_css );
}

sub log {
    my $self = shift;
    push @_, "\n" unless grep {/\n/} @_;
    $self->_output( @_ );
    return $self;
}

sub info {
    my $self = shift;
    return unless $self->verbose;
    return $self->log( @_ );
}

sub log_test {
    my $self = shift;
    return if $self->really_quiet;
    return $self->log( @_ );
}

sub log_test_info {
    my $self = shift;
    return if $self->quiet;
    return $self->log( @_ );
}

sub _output {
    my $self = shift;
    return if $self->silent;
    if (ref($_[0]) && ref( $_[0]) eq 'SCALAR') {
	# printing HTML:
	print { $self->stdout } ${ $_[0] };
    } else {
	unshift @_, '# ' if $self->escape_output;
	print { $self->stdout } @_;
    }
}


1;


__END__

=head1 DESCRIPTION

This provides html output formatting for TAP::Harness.

Documentation is rather sparse at the moment.

=cut

=head1 METHODS

=head2 CONSTRUCTOR

=head3 new( \%args )

=head2 ACCESSORS

All chaining L<accessors>:

=head3 verbosity( [ $v ] )

Verbosity level, as defined in L<TAP::Harness/new>:

     1   verbose        Print individual test results (and more) to STDOUT.
     0   normal
    -1   quiet          Suppress some test output (eg: test failures).
    -2   really quiet   Suppress everything but the HTML report.
    -3   silent         Suppress all output, including the HTML report.

Note that the report is also available via L</html>.

=head3 stdout( [ \*FH ] )

A filehandle for catching standard output.  Defaults to C<STDOUT>.

=head3 escape_output( [ $boolean ] )

If set, all output to L</stdout> is escaped.  This is probably only useful
if you're testing the formatter.
Defaults to C<0>.

=head3 html( [ \$html ] )

This is a reference to the scalar containing the html generated on the last
test run.  Useful if you have L</silent> on.

=head3 tests( [ \@test_files ] )

A list of test files we're running, set by L<TAP::Parser>.

=head3 session_class( [] )

Class to use for L<TAP::Parser> test sessions.  You probably won't need to use
this unless you're hacking or sub-classing the formatter.
Defaults to L<TAP::Formatter::HTML::Session>.

=head3 sessions( [ \@sessions ] )

Test sessions added by L<TAP::Parser>.  You probably won't need to use this
unless you're hacking or sub-classing the formatter.

=head3 template_processor( [ $processor ] )

The template processor to use.
Defaults to a TT2 L<Template> processor with the following config:

  COMPILE_DIR  => catdir( tempdir(), 'TAP-Formatter-HTML' ),
  COMPILE_EXT  => '.ttc',
  INCLUDE_PATH => join(':', @INC),

=head3 template( [ $file_name ] )

The template file to load.
Defaults to C<TAP/Formatter/HTML/default_report.tt2>.

=head3 css_uris( [ \@uris ] )

A list of L<URI>s (or strings) to include as external stylesheets in <style>
tags in the head of the document.
Defaults to:

  ['file:TAP/Formatter/HTML/default_report.css'];

=head3 js_uris( [ \@uris ] )

A list of L<URI>s (or strings) to include as external stylesheets in <style>
tags in the head of the document.
Defaults to:

  ['file:TAP/Formatter/HTML/jquery-1.2.3.pack.js'];

=head3 inline_css( [] )

If set, the formatter will include the CSS code in a <style> tag in the head of
the document.

=head3 inline_js( [ $javascript ] )

If set, the formatter will include the JavaScript code in a <script> tag in the
head of the document.

=head3 abs_file_paths( [ $ boolean ] )

If set, the formatter will attempt to convert any relative I<file> JS & css
URI's listed in L</css_uris> & L</js_uris> to absolute paths.  This is handy if
you'll be sending moving the HTML output around on your harddisk, (but not so
handy if you move it to another machine - see L</force_inline_css>).
Defaults to I<1>.

=head3 force_inline_css( [ $boolean ] )

If set, the formatter will attempt to slurp in any I<file> css URI's listed in
L</css_uris>, and append them to L</inline_css>.  This is handy if you'll be
sending the output around - that way you don't have to send a CSS file too.
Defaults to I<1>.

=head2 $html = $fmt->summary( $aggregator )

C<summary> produces a summary report after all tests are run.  C<$aggregator>
should be a L<TAP::Parser::Aggregator>.

This calls:

  $fmt->template_processor->process( $params )

Where C<$params> is a data structure containing:

  report      => %test_report
  js_uris     => @js_uris
  css_uris    => @js_uris
  incline_js  => $inline_js
  inline_css  => $inline_css
  formatter   => %formatter_info

The C<report> is the most complicated data structure, and will sooner or later
be documented in L</CUSTOMIZING>.

=head1 CUSTOMIZING

This section is not yet written.  Please look through the code if you want to
customize the templates, or sub-class.

=head1 BUGS

Please use http://rt.cpan.org to report any issues.

=head1 AUTHOR

Steve Purkis <spurkis@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2008 Steve Purkis <spurkis@cpan.org>, S Purkis Consulting Ltd.
All rights reserved.

This module is released under the same terms as Perl itself.

=head1 SEE ALSO

L<Test::TAP::HTMLMatrix> - the inspiration for this module.  Many good ideas
were borrowed from it.

L<TAP::Formatter::Console> - the default TAP formatter used by L<TAP::Harness>

=cut

