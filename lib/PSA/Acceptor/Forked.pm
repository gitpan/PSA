
=head1 NAME

PSA::Acceptor::Forker - base class for acceptors that fork

=head1 SYNOPSIS

 (see derived code)

=head1 DESCRIPTION

This is a base class, from which the L<PSA::Acceptor::AutoCGI> and
L<PSA::Acceptor::HTTP> classes derive.

This code adds to the basic acceptor;

=over

=item B<manager>

a property that contains a process manager, such as
L<PSA::ProcManager>.  This is a placeholder for now.

=item B<pre_fork>

a user-supplied code reference to be called before the acceptor forks
(eg, to close a database connection that might not handle the forking
well).  This is added to via the C<add_pre_fork()> method.

=item B<post_fork>

a user-supplied code reference to be called in new children (eg, to
open a new database connection).  This is added to via the
C<add_post_fork()> method.

=back

It is up to the B<manager> class to handle the forking, keeping enough
children running, killing off and monitoring old children, etc.

=cut

package PSA::Acceptor::Forked;

use base qw(PSA::Acceptor);

our $fields =
    {
     transient => {
		   manager => undef,
		   pre_fork => undef,
		   post_fork => undef,
		  },
    };

sub add_pre_fork {
    my $self = shift;
    push (@{$self->{pre_fork} ||= []}, @_);
}

sub add_post_fork {
    my $self = shift;
    push (@{$self->{post_fork} ||= []}, @_);
}


1;
