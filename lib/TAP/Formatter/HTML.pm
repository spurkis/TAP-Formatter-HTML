=head1 NAME

TAP::Formatter::HTML - Harness output delegate for html output

=head1 SYNOPSIS

 use TAP::Harness;
 my $harness = TAP::Harness->new({ formatter_class => 'TAP::Formatter::HTML' });

=cut

package TAP::Formatter::HTML;

use strict;
use warnings;

use File::Temp qw( tempfile tempdir );
use File::Spec::Functions qw( catdir );

use Template;
#use Template::Plugin::Cycle;

use base qw( TAP::Base );
use accessors qw( verbosity tests session_class sessions template template_file );

use constant default_session_class => 'TAP::Formatter::HTML::Session';

our $VERSION = '0.01';

# DEBUG:
use Data::Dumper 'Dumper';

sub _initialize {
    my ($self, $args) = @_;

    $args ||= {};
    $self->SUPER::_initialize($args);
    $self->verbosity(0)->session_class($self->default_session_class);
    $self->template( $self->create_template_processor )
      ->template_file( 'test-results.tt2' );

    return $self;
}

sub create_template_processor {
    my ($self) = @_;
    return Template->new(
			 COMPILE_DIR  => catdir( tempdir(), "TAP-Formatter-HTML-$$" ),
			 COMPILE_EXT  => '.ttc',
			 INCLUDE_PATH => catdir(qw( t data )),
			 EVAL_PERL    => 1,
			);
}


sub verbose      { shift->verbosity >= 1 }
sub quiet        { shift->verbosity <= -1 }
sub really_quiet { shift->verbosity <= -2 }
sub silent       { shift->verbosity <= -3 }

# Called by Test::Harness before any test output is generated.
sub prepare {
    my ($self, @tests) = @_;
    # warn ref($self) . "->prepare called with args:\n" . Dumper( \@tests );
    print STDERR 'running ' . scalar @tests . " tests\n";
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
    $self->generate_report( $aggregate );
}

sub generate_report {
    my ($self, $a) = @_;

    my $report = {
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
	$report->{$key} = $a->$key;
    }

    # add test results:
    foreach my $s (@{ $self->sessions }) {
	push @{$report->{tests}}, $s->as_report;
    }

    # TODO: process the template here
    my $html = $self->template->process( $self->template_file, { report => $report } )
      || die $self->template->error;

    print $html;
    #print "report: " . Dumper( $report );
}


1;

package TAP::Formatter::HTML::Session;

use strict;
use warnings;

use base qw( TAP::Base );
use accessors qw( test parser results closed );

# DEBUG:
use Data::Dumper 'Dumper';

sub _initialize {
    my ($self, $args) = @_;

    $args ||= {};
    $self->SUPER::_initialize($args);

    $self->results([])->closed(0);
    foreach my $arg (qw( test parser )) {
	$self->$arg($args->{$arg}) if defined $args->{$arg};
    }

    print STDERR $self->test, ":\n";

    return $self;
}

# Called by TAP::?? to create a result after a session is opened
sub result {
    my ($self, $result) = @_;
    #warn ref($self) . "->result called with args: " . Dumper( $result );
    print STDERR $result->as_string, "\n";
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
    return {
	    test => $self->test,
	    results => $self->results,
	   };
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

Copyright (c) 2008 S Purkis Consulting Ltd.

This module is released under the same terms as Perl itself.

=cut

