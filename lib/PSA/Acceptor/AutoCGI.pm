
package PSA::Acceptor::AutoCGI;
use strict;
use Carp;

=head1 NAME

PSA::Acceptor::AutoCGI - Detect CGI method and return requests

=head1 SYNOPSIS

 my $acceptor = PSA::Acceptor::AutoCGI->new();

 while (my $request = $acceptor->get_request() ) {

     my $psa = PSA->new(request => $request, ...);

 }

=head1 DESCRIPTION

PSA::Acceptor::AutoCGI is a PSA::Request object factory.  On
invocation, it determines whether FastCGI, mod_perl or standard CGI
invocation is being used.

=head1 METHODS

=over

=item PSA::Acceptor::AutoCGI->new(socket => [ 'pathname' ])

Returns a new acceptor object.  If 'sitename' is given, then the
program is considered to be an external FastCGI daemon.

=cut

use IO::Handle;
use base qw(PSA::Acceptor::Forked);
use PSA::Request::CGI;

our $fields = {
	       transient => {
			     fastcgi => undef,
			    },
	       string => {
			  socket => undef,
			  renamesock => undef,   # for re-exec
			  bind => undef,
			  base => undef,
			 },
	       int => {
		       nproc => undef,
		       need_post => undef,
		       pm_active => undef,
		       parent_pm => undef,
		      },
	      };

sub _fill_init_default {

    my $self = shift;
    my $x;

    if (not$self->get_socket and ($x= $ENV{FASTCGI_SOCKET_PATH})) {
	$self->set_socket($x);
    }

    if (not $self->get_nproc and ($x= $ENV{FASTCGI_NPROC})) {
	$self->set_nproc($x);
    }

    return $self->SUPER::_fill_init_default();

}

sub new {
    my $class = shift;
    my $self;

    $self = $class->SUPER::new(@_);

    if ( -S STDIN or $self->socket or $self->bind ) {

	eval "use FCGI";
	carp "STDIN is a socket, but could not load FCGI module"
	    if $@;

	# default 1000 hits to a single instance of a FastCGI program
	$self->set_max_age(1000);

	# Create filehandles for the acceptor
	my ($out, $err) = map { IO::Handle->new() } (1..2);

	my $sock = 0;
	if ($self->socket) {
	    print STDERR "${0}[$$]: Socket is ".$self->socket."\n";
	    if (my $pid = delete $ENV{PSA_REEXEC}) {
		print STDERR "${0}[$$]: taking over from parent $pid\n";
		$self->set_parent_pm($pid);
		$self->set_renamesock($self->socket);
		$self->set_socket($self->socket.".new$$");
		delete $ENV{PSA_REEXEC};
	    }
	    umask(0);
	    $sock = FCGI::OpenSocket($self->socket, 100)
		or die $!;
	    umask(022);
	    print STDERR "${0}[$$]: listening on ".$self->socket."\n";
	    $self->set_nproc(5) unless $self->nproc;
	}

	my %env;
	$self->{fastcgi} =
	    {
	     stdout => $out,
	     stderr => $err,
	     env => \%env,
	     request => FCGI::Request
	     (\*STDIN, $out, $err, \%env,
	      $sock,
	      &FCGI::FAIL_ACCEPT_ON_INTR,
	     ),
	     hits => 0,
	     script_age => ((stat $0)[10])||0,
	    };
    } elsif ( -t STDIN && !$ENV{SPIT_IT_OUT}) {

	eval "use PSA::Acceptor::Dummy";              { die $@ if $@ }

	$self = PSA::Acceptor::Dummy->new(@_);

	# Heh... should fork some xterms
	if ($self->nproc) {
	}
    }

    if ( defined($self->nproc) && $self->nproc > 1 ) {

eval "use PSA::ProcManager";
	die "nproc set, Process Manager failed to load; $@" if $@;

	$self->set_manager
	    (
	     PSA::ProcManager->new ({ n_processes => $self->nproc,
				    })
	    );

	$self->manager->pm_write_pid_file($self->socket.".pid");
    }

    return $self;
}

# this was part of a configuration re-loading system that never
# worked.  FIXME.
sub rename_socket {
    my $self = shift;
    print STDERR "${0}[$$]: renaming socket\n";
    ($a,$b) = ($self->socket, $self->renamesock);
    rename($a,$b) or die "rename($a, $b) failed; $!";

    my $pid = $self->get_parent_pm;
    print STDERR "${0}[$$]: signalling parent $pid\n";
    kill 15, $pid;

    $self->set_socket($b);
    $self->set_renamesock();
}

=item $acceptor->get_request

Returns a PSA::Request object, or undef if there are none.

=cut

sub get_request {
    my $self = shift;

    $self->SUPER::get_request() or return undef;

    if ( my $f = $self->{fastcgi} ) {

	if ($self->renamesock) {
	    print STDERR "${0}[$$]: renaming socket\n";
	    ($a,$b) = ($self->socket, $self->renamesock);
	    rename($a,$b) or die "rename($a, $b) failed; $!";

	    my $pid = $self->get_parent_pm;
	    print STDERR "${0}[$$]: signalling parent $pid\n";
	    kill 15, $pid;

	    $self->set_socket($b);
	    $self->set_renamesock();
	}
	if ($self->manager) {
	    my $x;
	    if (!$self->manager->active) {
		$x = 1;
		$_->() foreach @{ $self->{pre_fork} || [] };
	    }
	    $self->manager->pre_accept_hook();
	    if ($x) {
		$_->() foreach @{ $self->{post_fork} || [] };
	    }
	}
	# Get a FastCGI request
	($f->{request}->Accept() == 0) or return undef;

	if ($self->manager) {
	    $self->manager->post_accept_hook();
	}

    }

    # Call the CGI request constructor and return it
    return PSA::Request::CGI->fetch
	(base => ($self->get_base || ""),
	 ($self->{fastcgi} ? (env => $self->{fastcgi}{env}) : ()),
	);
}

=item $acceptor->output_fd

Returns the filehandle (either an IO::Handle or a ref GLOB) to write
to to respond to this request

=cut

sub output_fd {
    my $self = shift;

    if ( my $f = $self->{fastcgi}) {
	return $f->{stdout};
    } else {
	return \*STDOUT;
    }
}

sub flush {
    my $self = shift;
    if ( my $f = $self->{fastcgi} ) {
	$f->{request}->Flush();
    } else {
	$self->output_fd->flush();
    }
}

37;

__END__

=back

=head1 SEE ALSO

L<PSA>, L<PSA::Acceptor>, L<PSA::Acceptor::Dummy>, L<PSA::Request::CGI>

=cut

