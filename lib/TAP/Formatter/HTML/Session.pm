package TAP::Formatter::HTML::Session;

use strict;
use warnings;

use base qw( TAP::Base );
use accessors qw( test formatter parser results html_id meta closed );

# DEBUG:
use Data::Dumper 'Dumper';

sub _initialize {
    my ($self, $args) = @_;

    $args ||= {};
    $self->SUPER::_initialize($args);

    $self->results([])->meta({})->closed(0);
    foreach my $arg (qw( test parser formatter )) {
	$self->$arg($args->{$arg}) if defined $args->{$arg};
    }

    # make referring to it in HTML easy:
    my $html_id = $self->test;
    $html_id    =~ s/[^a-zA-Z\d-]/-/g;
    $self->html_id( $html_id );

    $self->info( $self->test, ':' );

    return $self;
}

# Called by TAP::?? to create a result after a session is opened
sub result {
    my ($self, $result) = @_;
    #warn ref($self) . "->result called with args: " . Dumper( $result );

    if ($result->is_test) {
	$self->log( $result->as_string );
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
    } else {
	$self->info( $result->as_string );
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
    $self->formatter->log_test(@args);
}

sub info {
    my ($self, @args) = @_;
    $self->formatter->log_test_info(@args);
}


1;
