=head1 NAME

PSA::Config - Site configuration

=head1 SYNOPSIS

 print $psa->config->whatever

 # or, in a PSA page;

 my $psa = shift;
 if ($psa->config->foo) {

 }

=head1 DESCRIPTION

PSA::Config provides access to the application level configuration.
Currently, this is achieved via the YAML module.

=cut

package PSA::Config;

use strict;

use YAML;

#use Want;
use Carp qw(croak);

sub new {
    my $package = shift;
    my $conffile = (shift) || "etc/psa.yml";

    my $self;
    my @lines;

    if (open FH, $conffile) {
	while (<FH>) {
	    next if /^#/;   # comments
	    next if /^$/;   # blank lines
	    push @lines, $_;
	}
	close FH;

	my @tmpcfg = YAML::thaw(join '', @lines);
	$self = \%{$tmpcfg[0]}
    } else {
	warn "Failed to open $conffile; using defaults for everything";
	$self = {};
    }

    bless $self, $package;
    return $self;
}

# helper function for T2::Storage::get_dsn_info


#our $AUTOLOAD;
#no warnings;
#
#sub AUTOLOAD :lvalue {
#    my $self = shift;
#
#    $AUTOLOAD =~ s{.*::}{};
#    print STDERR "Bong!  $AUTOLOAD\n";
#
#    if (want(qw(LVALUE ASSIGN))) {
#	$self->{$AUTOLOAD} = want("ASSIGN");
#	lnoreturn;
#    } elsif (want("REFSCALAR")) {
#	rreturn \$self->{$AUTOLOAD};
#    } elsif (want("SCALAR")) {
#	rreturn $self->{$AUTOLOAD};
#    } else {
#	croak "What do you want from me?";
#    }
#    return;
#}
#
#sub DESTROY { print STDERR "Bang!\n"; }


1;

=cut
