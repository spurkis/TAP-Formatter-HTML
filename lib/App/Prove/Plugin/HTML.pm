package App::Prove::Plugin::HTML;

=head1 NAME

App::Prove::Plugin::HTML - prove plugin for TAP::Formatter::HTML

=head1 SYNOPSIS

 # this is currently in alpha, cmdline params may change!
 % prove -PHTML=output.html -m -Q --formatter=TAP::Formatter::HTML

=cut

use strict;
use warnings;

our $VERSION = '0.07';

sub import {
    my ($class, @args) = @_;
    my %args;

    if (scalar(@args) % 2) {
	# odd # args => manual parsing
	$args{outfile}          = shift @args;
	$args{force_inline_css} = shift @args;
	$args{css_uris}         = shift @args;
	$args{js_uris}          = shift @args;
	$args{template}         = shift @args;
    } else {
	# even # args => we've got a hash:
	%args = @args;
    }

    # set ENV vars here - it's the easiest way to
    # pass variables to TAP::Formatter::HTML.
    foreach my $arg (keys %args) {
	$ENV{"TAP_FORMATTER_HTML_".uc($arg)} = $args{$arg};
    }

    return $class;
}

1;

__END__

