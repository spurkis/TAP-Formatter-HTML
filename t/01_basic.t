use strict;
use warnings;

use lib 'lib';

use Test::More 'no_plan';

use TAP::Harness;
use_ok( 'TAP::Formatter::HTML' );

# Don't escape output here... this test should pass!
my @tests = glob( 't/data/01*.pl' );
my $h = TAP::Harness->new({ merge => 1,
			    formatter_class => 'TAP::Formatter::HTML' });
$h->runtests(@tests);

