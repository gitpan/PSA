
=head1 NAME

PSA::Init - utility functions for writing PSA handlers

=head1 SYNOPSIS

 # simplest use - get cmdline args and supply
 use PSA qw(Init);
 PSA::Init::run(%options, @ARGV);

 # more incremental use

=head1 DESCRIPTION

C<PSA::Init> is the handler called by the F<psa> wrapper script.

It is responsible for auto-detecting the site layout, as well as
loading the configuration, switching users and so on.

=cut

package PSA::Init;

use strict;
use Carp;

# this global stores program options.  as initialisation is a
# per-process thing, it is ok for this to be a global.

# leaving it as a single global should aid refactoring it out if the
# need arises.
our %o;

sub run($$) {
    my $o = shift;
    $o and ref($o) eq "HASH"
	or carp "usage: PSA::Init::run({ options }, $loc)";
    %o = %{(shift)};

    my $location = shift || ".";
    @ARGV && carp "extra junk at end of command: @ARGV";

    # TO-DO: load master config, fork for each PSA site on system
    if ( $o{all} ) {
	require 'PSA/All.pm';
	mutter "PSA::All->$o{action}";
	if ( PSA::All->$o{action}(\%o) ) {
	    say "finished $o{action} operation for all sites";
	    exit(0);
	}
    }

    $o{action} or carp "no action supplied!";

    # otherwise, start with $o{action}
    PSA->$o{action}(\%o);
}

( -e $location ) or carp "not found: $location";
if ( -f $location ) {
    # auto-detect site root, run as filter
    fixme;
}

# SANITY CONDITION - CWD IS ALWAYS SITE ROOT
chdir($location);
my $config = PSA::Config->new($o{config_file});

# get per-phase defaults, if phases are defined - do this before
# dropping privileges to allow per-site auth
my $phase;
if ( $config->{phases} ) {
    no re 'exec';

    my $phase = $o{phase} or $config->{default_phase};

    if ( !$phase ) {
	if ( my $re = $config->{phase_re} ) {
	    require 'Cwd';
	    my $dir = getcwd;
	    if ( ref $re ) {
		while ( my ($key, $value) = each %$re_table ) {
		    if ( $dir =~ m/$key/ ) {
			$phase = $value;
			last;
		    }
		}
		$phase
		    or carp("no regular expressions in the "
			    ."phase_re hash matched our cwd ($dir)");
	    } else {
		($phase) = ($dir =~ /$re/)
		    or carp "qr/$re/ didn't match $dir; phase unknown";
	    }
	} else {
	    carp "phases defined in config file, but not selected!";
	}
    }

    exists $config->{phase}{$phase}
	or carp "selected phase `$phase' not defined";
}

$conf = sub {
    my @sp = ( \%o,
	       ($phase ? $config->{phases}{$phase} : ()),
	       $config );
    while ( my $thing = shift ) {
	@sp = map { (ref $_ and UNIVERSAL::isa($_, "HASH") and
		     defined $_->{$thing}) ? $_->{$thing} : undef }
	    @sp;
    }
    if ( wantarray ) {
	@sp;
    } else {
	(grep { defined } @sp)[0];
    }
};

# TO-DO - auto-detect/select uid to run as
if ( !$< or !$> or $conf->("auth") ) {
    require 'PSA/Auth.pm';
    PSA::Auth->boot($conf);
}

#---- PERMISSION PARANOIA MODE ENDS ----

# allow local Perl includes
for my $libpath ( qw(lib inc src) ) {
    unshift @INC, $libpath if -d $libpath && -x _;
}

#----
# if monitor is running, send this request to it.
my $monitor = PSA::Monitor->new($config);
if ( $monitor->ping ) {
    $monitor->handle($config);
}

# initialise modules
for my $module ( @modules ) {
    $module =~ s{::}{/}g;
    require 'PSA/'.$module.".pm";
}

# initialise logging

if ( $kill ) {
    # load PID information and get jiggy with signals

} elsif ( $reattach ) {
    # start monitor on active process

} else {
    # normal start

}

# initialise request IO listener



sub fixme {
    barf "sorry, the requested feature hasn't been implemented yet";
}

__END__

