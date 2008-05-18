=head1 NAME

TAP::Formatter::HTML - Harness output delegate for html output

=head1 SYNOPSIS

 use TAP::Harness;
 my $harness = TAP::Harness->new({ formatter_class => 'TAP::Formatter::HTML' });

 # if you want stderr too:
 my $harness = TAP::Harness->new({ formatter_class => 'TAP::Formatter::HTML',
                                   merge => 1 });

=cut

package TAP::Formatter::HTML;

use strict;
use warnings;

use POSIX qw( ceil );
use File::Temp qw( tempfile tempdir );
use File::Spec::Functions qw( catdir catfile file_name_is_absolute rel2abs );

use URI;
use Template;

# DEBUG:
#use Data::Dumper 'Dumper';

use base qw( TAP::Base );
use accessors qw( verbosity tests session_class sessions template template_file
		  css_uris js_uris inline_css inline_js abs_file_paths force_inline_css );

use constant default_session_class => 'TAP::Formatter::HTML::Session';
use constant default_template      => 'TAP/Formatter/HTML/default_report.tt2';
use constant default_js_uris       => ['file:TAP/Formatter/HTML/jquery-1.2.3.pack.js'];
use constant default_css_uris      => ['file:TAP/Formatter/HTML/default_report.css'];
use constant default_inline_js     => '';
use constant default_inline_css    => '';
use constant default_template_processor =>
  Template->new(
		COMPILE_DIR  => catdir( tempdir(), "TAP-Formatter-HTML-$$" ),
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
         ->abs_file_paths( 1 )
         ->force_inline_css( 1 )
         ->session_class( $self->default_session_class )
         ->template( $self->default_template_processor )
         ->template_file( $self->default_template )
         ->js_uris( $self->default_js_uris )
         ->css_uris( $self->default_css_uris )
         ->inline_js( $self->default_inline_js )
	 ->inline_css( $self->default_inline_css );

    return $self;
}

sub verbose      { shift->verbosity >=  1 }
sub quiet        { shift->verbosity <= -1 }
sub really_quiet { shift->verbosity <= -2 }
sub silent       { shift->verbosity <= -3 }

# Called by Test::Harness before any test output is generated.
sub prepare {
    my ($self, @tests) = @_;
    # warn ref($self) . "->prepare called with args:\n" . Dumper( \@tests );
    $self->log( 'running ', scalar @tests, ' tests' );
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
    my $session = $self->session_class->new({ test => $test, parser => $parser });
    push @{ $self->sessions }, $session;
    return $session;
}

#  $harness->summary( $aggregate );
#
# C<summary> prints the summary report after all tests are run.  The argument is
# an aggregate.
sub summary {
    my ($self, $aggregate) = @_;
    #warn ref($self) . "->summary called with args: " . Dumper( [$aggregate] );

    # farmed out to make sub-classing easy:
    my $report = $self->prepare_report( $aggregate );
    my $html   = $self->generate_report( $report );

    return $html;
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
		 };

    return $self->template->process( $self->template_file, $params )
      || die $self->template->error;
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
    $self->log("slurping css files inline");

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
    my ($self, @args) = @_;
    # poor man's logger, but less deps is great!
    print STDERR '# ', @args, "\n";
    return $self;
}


1;

package TAP::Formatter::HTML::Session;

use strict;
use warnings;

use base qw( TAP::Base );
use accessors qw( test parser results html_id meta closed );

# DEBUG:
use Data::Dumper 'Dumper';

sub _initialize {
    my ($self, $args) = @_;

    $args ||= {};
    $self->SUPER::_initialize($args);

    $self->results([])->meta({})->closed(0);
    foreach my $arg (qw( test parser )) {
	$self->$arg($args->{$arg}) if defined $args->{$arg};
    }

    # make referring to it in HTML easy:
    my $html_id = $self->test;
    $html_id    =~ s/[^a-zA-Z\d-]/-/g;
    $self->html_id( $html_id );

    $self->log( $self->test, ':' );

    return $self;
}

# Called by TAP::?? to create a result after a session is opened
sub result {
    my ($self, $result) = @_;
    #warn ref($self) . "->result called with args: " . Dumper( $result );
    $self->log( $result->as_string );

    if ($result->is_test) {
	# make referring to it in HTML easy:
	$result->{html_id} = $self->html_id . '-' . $result->number;

	# set this to avoid the hassle of recalculating it in the template:
	$result->{test_status}  = $result->has_todo ? 'todo-' : '';
	$result->{test_status} .= $result->has_skip ? 'skip-' : '';
	$result->{test_status} .= $result->is_actual_ok ? 'ok' : 'not-ok';

	# keep track of passes (including unplanned!) for percent_passed calcs:
	if ($result->is_ok || $result->is_unplanned && $result->is_actual_ok) {
	    $self->meta->{passed_including_unplanned}++;
	}

	# mark passed todo tests for easy reference:
	if ($result->has_todo && $result->is_actual_ok) {
	    $result->{todo_passed} = 1;
	}
    }


    push @{ $self->results }, $result;
    return;
}

# Called by TAP::?? to indicate there are no more test results coming
sub close_test {
    my ($self, @args) = @_;
    # warn ref($self) . "->close_test called with args: " . Dumper( [@args] );
    #print STDERR 'end of: ', $self->test, "\n\n";
    $self->closed(1);
    return;
}

sub as_report {
    my ($self) = @_;
    my $p = $self->parser;
    my $r = {
	    test => $self->test,
	    results => $self->results,
	   };

    # add parser info:
    for my $key (qw(
		    tests_planned
		    tests_run
		    start_time
		    end_time
		    skip_all
		    has_problems
		    passed
		    failed
		    todo_passed
		    actual_passed
		    actual_failed
		    wait
		    exit
		   )) {
	$r->{$key} = $p->$key;
    }

    $r->{num_parse_errors} = scalar $p->parse_errors;
    $r->{parse_errors} = [ $p->parse_errors ];
    $r->{passed_tests} = [ $p->passed ];
    $r->{failed_tests} = [ $p->failed ];

    # do some other handy calcs:
    $r->{test_status} = $r->{has_problems} ? 'failed' : 'passed';
    $r->{elapsed_time} = $r->{end_time} - $r->{start_time};
    $r->{severity} = '';
    if ($r->{tests_planned}) {
	# Calculate percentage passed as # passes *including* unplanned passes
	# so we can get > 100% -- this can be a good indicator as to why a test
	# failed!
	my $passed_incl_unplanned = $self->meta->{passed_including_unplanned} || 0;
	my $p = $r->{percent_passed} = sprintf('%.1f', $passed_incl_unplanned / $r->{tests_planned} * 100);
	if ($p != 100) {
	    my $s;
	    if ($p < 25)    { $s = 'very-high' }
	    elsif ($p < 50) { $s = 'high' }
	    elsif ($p < 75) { $s = 'med' }
	    elsif ($p < 95) { $s = 'low' }
	    else            { $s = 'very-low' }
	    # classify >100% as very-low
	    $r->{severity} = $s;
	}
    } elsif ($r->{skip_all}) {
	; # do nothing
    } else {
	$r->{percent_passed} = 0;
	$r->{severity} = 'very-high';
    }

    if (my $num = $r->{num_parse_errors}) {
	if ($num == 1 && ! $p->is_good_plan) {
	    $r->{severity} ||= 'low'; # prefer value set calculating % passed
	} else {
	    $r->{severity} = 'very-high';
	}
    }

    # check for scripts that died abnormally:
    if ($r->{exit} && $r->{exit} == 255 && $p->is_good_plan) {
	$r->{severity} ||= 'very-high';
    }

    # catch-all:
    if ($r->{has_problems}) {
	$r->{severity} ||= 'high';
    }

    return $r;
}

sub log {
    my ($self, @args) = @_;
    # poor man's logger, but less deps is great!
    print STDERR '# ', @args, "\n";
}


1;


__END__

=head1 DESCRIPTION

This provides html orientated output formatting for TAP::Harness.

=cut

=head1 METHODS

not yet documented...

=head1 AUTHOR

Steve Purkis <spurkis@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2008 S Purkis Consulting Ltd.  All rights reserved.

This module is released under the same terms as Perl itself.

=cut

