#   -*- perl -*-

package PSA::POE;

=head1 NAME

PSA::POE - POE process manager for PSA

=head1 SYNOPSIS

  use PSA qw(POE);

  my $poe_manager = PSA::POE->new
      ( cache => PSA::Cache->new (base_dir => "psa-bin"),
        entry_point => "whassap",  # or make _start.poe
        args => [ ... ],
      );

  $poe_kernel->run();

=head1 DESCRIPTION

PSA::POE acts as a bridge between POE and PSA.  A PSA::POE object B<is
a> PSA object.  It uses the POE::Session::PSA class to bridge between
PSA and POE.

=cut

use base qw(PSA);  # oh boy!
use POE qw(Session::PSA);  # teehee

our $fields = {
	       ref => {
		       thread => { class => "POE::Session::PSA" },
		      },
	       perl_dump => {
			     args => undef,
			    },
	      };

=head1 INTERFACE

=head2 B<PSA::POE-E<gt>new(option =E<gt> value...)>

Creates a new PSA POE session, and returns it.

=cut

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);

    my ($root, $ep) = ($self->entry_point||"")
	=~ m{^(?:(.*)/)?(.*?)(\..*)?$};

    $root ||= "";

    $self->set_thread
	( POE::Session::PSA->create
	  ( psa => $self,
	    cache => $self->cache,
	    root => $root,
	    args => scalar($self->args),
	    entry_point => $ep,
	    #options => { trace => 1, debug => 1 },
	  )
	);

    return $self;
}

sub yield {
    my $self = shift;
    $poe_kernel->post($self->thread, @_);
}

sub run_queued {
    # do nothing...
}

sub spawn {
    my $self = shift;
    my $copy = $self->new(heap => {%{$self->heap}}, run_depth => 0, @_);

}

use Scalar::Util qw(refaddr);

sub _child {
    my $self = shift;
    my $child = shift;
    return unless $self->{waiting};

    if (my $list = delete $self->{waiting}{refaddr($child)}) {
	$_->[0]->yield(@{$_}[1..$#$_]) foreach @$list;
    }
}

sub wait {
    my $self = shift;
    my $child = shift;

    unshift @_, $self;
    push @{ ${$self->{waiting} ||= {}}{refaddr($child->thread)} ||= []},
	\@_;
}

1;

__END__
