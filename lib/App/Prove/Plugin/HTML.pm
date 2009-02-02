package App::Prove::Plugin::HTML;

=head1 NAME

App::Prove::Plugin::HTML - a prove plugin for HTML output

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

=head1 DESCRIPTION

This is a quick & dirty first attempt at making L<TAP::Formatter::HTML> a bit
easier to use.  It will likely change.

My original goal was to be able to specify all the args on the cmdline, ala:

  % prove --html=output.html

And have this map onto:

  % prove -PHTML=output.html -m --formatter=TAP::Formatter::HTML

Though this is currently not possible with the way the L<App::Prove> plugin
system works.

=head1 BUGS

Please use http://rt.cpan.org to report any issues.

=head1 AUTHOR

Steve Purkis <spurkis@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2008-9 Steve Purkis <spurkis@cpan.org>, S Purkis Consulting Ltd.
All rights reserved.

This module is released under the same terms as Perl itself.

=head1 SEE ALSO

L<prove>, L<App::Prove>, L<TAP::Formatter::HTML>

=cut
