=head1 NAME

PSA::Config - Site configuration

=head1 SYNOPSIS

 # load the config file - don't process anything
 my $config = PSA::Config->new;

 # setup Perl and auto-detect administration options
 $config->engage;

=head1 DESCRIPTION

PSA::Config provides access to the application level configuration.
Currently, this is achieved via the YAML module.

=cut

package PSA::Config;

use strict;
use Cwd;
use Sys::Hostname;
use Set::Object;
use Scalar::Util qw(reftype blessed);

use YAML;

#use Want;
use Carp qw(croak);

=head1 CONSTRUCTOR

=over

=item B<PSA::Config-E<gt>new([$filename])>

Loads the config file.  The default location is F<etc/psa.yml>, but
this can be over-ridden by passing in a location.

This is basically a thin wrapper for L<YAML/Load>.  Note that this is
B<not> a singleton method.

=cut

sub new {
    my $package = shift;
    my $conffile = (shift) || "etc/psa.yml";

    my $self;
    my @lines;

    if (open FH, $conffile) {
	while (<FH>) {
	    #next if /^#/;   # comments
	    #next if /^$/;   # blank lines
	    push @lines, $_;
	}
	close FH;

	eval {
	    my @tmpcfg = YAML::thaw(join '', @lines);
	    $self = \%{$tmpcfg[0]}
	};
	if ( $@ ) {
	    warn "PSA CONFIG ERROR - YAML exception on $conffile";
	    die $@;
	}
    } else {
	warn "Failed to open $conffile; using defaults for everything";
	$self = {};
    }

    bless $self, $package;

    $self->autoconf(shift);

    return $self;
}

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

sub say;
sub moan;

BEGIN {
    *say = sub {
	my $what = shift;
	if ( -t STDERR and !$ENV{SHUT_UP} ) {
	    print STDERR __PACKAGE__.": $what\n";
	}
    } unless defined &say;

    *moan = sub { &say("WARNING: @_"); }
	unless defined &say;
}

=head2 OBJECT METHODS

=over

=item B<$config-E<gt>engage>

This method does all the auto-configuration normally needed for most
startups.  This is divided between C<-E<gt>autoconf()> and
C<-E<gt>perlconf()> methods, in order, as described below:

=cut

sub engage {
    my $self = shift;
    $self->autoconf;
    $self->perlconf;
}

=item B<$config-E<gt>autoconf>

The purpose of C<autoconf()> is to automatically determine, from the
configuration file and current working directory, what extra
configurtion options should be set.

This is discussed in terms of the current site I<phase>.  Normally,
projects will use between two and four phases of development for each
cycle, such as I<development>, I<snapshot>, I<preview>, I<testing>,
and I<production>.  The number of phases, etc are all of course quite
arbirary This is configured by defining a map;

 phase_rules:
   ? '.*prd:.*/prod'
   : prod

   ? '.*prd:.*/test'
   : test

   ? '.*tst:.*/prev'
   : snap

   ? '.*:.*/dev'
   : dev

Keys in the map are strings to match against the C<hostname:PSA root>
pair.  Then, all you do is add extra config data in the C<phases> key;

 phases:
   prod:
     acceptor: { nproc: 5, socket: ':6000' }
   test:
     acceptor: { nproc: 2, socket: 6001 }
   snap:
     acceptor: { nproc: 2, socket: 'var/appSocket' }
   dev:
     acceptor: { nproc: 1, socket: 'var/appSocket' }

The entire structure under each I<phase> is copied into the root
config hash.  So, if the above configuration settings were made, and
the application started via the L<psa> wrapper in F</abc/apps/prev> on
the host C<blahtst>, then the C<snap> phase would be automatically
selected.  So, it would be equivalent to setting:

 acceptor:
   nproc: 2
   socket: 'var/appSocket'

(note; alternate YAML styles are showed above for brevity)

=cut

sub autoconf {
    my $self = shift;
    my $phase = shift;

    if ( defined $phase ) {
	if ( $phase ) {
	    say "forcing phase of `$phase'";
	} else {
	    say "forcing no phase";
	}
    }

    elsif ( my $map = $self->{phase_rules} ) {
	my $loc = hostname . ":" . cwd;
	keys %$map;
	while ( my ($re, $dest) = each %$map ) {
	    if ( $loc =~ m/$re/ ) {
		eval '$phase = "'.$dest.'"';
		die("phase_rules value `$dest' does not compile;"
		    ."$@") if $@;
		last;
	    }
	}
	if ( $phase ) {
	    say "detected phase of `$phase'";
	} else {
	    moan "location `$loc' didn't match any phase rules";
	    say "continuing without phase config";
	}
    }

    # now, we know the phase, so overlay the config.
    if ( $phase ) {
	$self->{phase} = $phase;
	my $phases;
	if ( ($phases = $self->{phases}) and (exists $phases->{$phase}) ) {
	    my $config = $phases->{$phase};
	    $self->apply($config);
	} else {
	    die "no phase config found for phase `$phase'";
	}
    }
}

=item B<$config-E<gt>perlconf>

This is a general purpose method which looks for some standard options
designed to configure Perl in some way, such as setting include paths.

For secure invocations of L<psa>, this is always called after
L<PSA::Auth> (responsible for dropping privileges) has been loaded.

=cut

sub perlconf {
    my $self = shift;
    if ( my $perlconf = $self->{perl} ) {
	if ( exists $perlconf->{INC} ) {
	    if ( blessed $perlconf->{INC} ) {
		my $ref = (ref $self->{INC});
		eval "use $ref;"; die $@ if $@;
	    }
	    elsif ( ref $perlconf->{INC} eq "ARRAY" ) {
		unshift @INC, @{ $self->{INC} };
	    } else {
		die "bogon in INC: $perlconf->{INC}";
	    }
	}
    }
}

#---------------------------------------------------------------------
#  PSA::Config->apply($config)
# merges one data structure with the passed one.  ie, everything from
# $config is recursively copied into $self.
#---------------------------------------------------------------------
sub apply {
    my $self = shift;
    my $config = shift;

    my @stack_s = \$self;
    my @stack_c = \$config;

    my $seen = Set::Object->new(@stack_c);
    while ( defined (my $c = pop @stack_c) ) {
	my $s = pop @stack_s;

	if ( defined $$c and not defined $$s ) {
	    $$s = $$c;
	} elsif ( ref $$c ) {
	    if ( reftype $$c eq "HASH" ) {
		$$s = {} unless do{ my$r=reftype($$s); $r&&($r eq "HASH")};
		while ( my $key = each %$$c ) {
		    if ( blessed(${$c}->{$key}) or !ref(${$c}->{$key}) ) {
			${$s}->{$key} = ${$c}->{$key}
			    if defined (${$c}->{$key})
		    }
		    elsif ( $seen->insert(${$c}->{$key}) ) {
			push @stack_c, \(${$c}->{$key});
			push @stack_s, \(${$s}->{$key});
		    }
		}
	    }
	    elsif ( reftype $$c eq "ARRAY" ) {
		$$s = [] unless do{ my$r=reftype($$s); $r&&($r eq "ARRAY")};
		for ( my $i = 0; $i <= $#$$c; $i++ ) {
		    if ( blessed(${$c}->[$i]) or !ref(${$c}->[$i]) ) {
			${$s}->[$i] = ${$c}->[$i]
			    if defined (${$c}->[$i])
		    }
		    elsif ( $seen->insert(${$c}->[$i]) ) {
			push @stack_c, \(${$c}->[$i]);
			push @stack_s, \(${$s}->[$i]);
		    }
		}
	    } else {
		die("can't handle a reftype of ".reftype($$c)
		    ." in autoconf");
	    }
	} elsif ( defined $$c ) {
	    $$s = $$c;
	}
    }

    return $self;
}

1;

__END__

=back

=cut

=head1 SEE ALSO

L<PSA>, L<PSA::Intro>, L<PSA::Installation>

L<YAML>

=cut

