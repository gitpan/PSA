
package PSA::ProcManager;

=head1 NAME

PSA::ProcManager - pre-forking process manager for PSA

=head1 SYNOPSIS

  my $acceptor = PSA::Acceptor::AutoCGI->new(nproc => 5);

=head1 DESCRIPTION

This module simply wraps the FastCGI process manager
(FCGI::ProcManager) and provides a couple of functions to play well
with the PSA::Acceptor::AutoCGI class.

=cut

use base qw(FCGI::ProcManager);

sub new {
    my $class = shift;
    my $args = shift;
    my $re_exec = [ $0 ];
    if ($args) {
	$re_exec = delete $args->{re_exec};
    }
    my $self = $class->SUPER::new($args, @_);
    $self->{re_exec} = $re_exec;
    return $self;
}

sub sig_manager {
    my $self = shift;
    my $signal = shift;

    if ($signal eq "USR1") {
	#FIXME - this doesn't work :)
	my $dollar = $$;
	if (my $pid = fork()) {
	    $self->pm_notify("psa[$$]: USR1 received; starting "
			     ."rebirth to pid $pid");
	    return;
	} else {
	    $ENV{PSA_REEXEC} = $dollar;
	    exec(@{$self->{re_exec}||[]});
	}
    #} elsif ($signal eq "USR2") {
	#$self->pm_notify("psa[$$]: transaction requires ");
    } else {
	return $self->SUPER::sig_manager($signal, @_);
    }

};

sub pre_accept_hook {
    my $self = shift;

    if ( $self->{managing} ) {
	$self->pm_post_dispatch();
    } else {
	$self->{managing} = 1;
	$self->pm_manage();
    }
}

sub active {
    my $self = shift;
    return $self->{managing};
}

sub post_accept_hook {
    my $self = shift;

    if ( $self->{managing} ) {
	$self->pm_pre_dispatch();
    }
}

1;
