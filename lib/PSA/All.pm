
=head1 NAME

PSA::All - manage multiple PSA-style applications on a system

=head1 SYNOPSIS

Normal commandline invocation:

 psa --all --daemon

From a script:

 use PSA qw(Init);
 PSA::Init::run({ all => 1, daemon => 1 }, "path");

=head1 DESCRIPTION

PSA::All will eventually be a simple way to start a number of PSA
applications in one hit, via a master configuration file in
F</etc/psa.yml> or F<~/.psa.conf>.

For now, this is a placeholder.

=cut

package PSA::All;


1;
