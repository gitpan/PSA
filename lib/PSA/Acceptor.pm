
package PSA::Acceptor;

=head1 NAME

PSA::Acceptor - Base class for back-ends to accept PSA requests

=head1 SYNOPSIS

 my $acceptor = PSA::Acceptor::AutoCGI->new();

=head1 DESCRIPTION

Normally, you create an instance of a sub-class of this module.
Currently the only acceptors that has been written is
L<PSA::Acceptor::AutoCGI>.  There should be a L<PSA::Acceptor::TCP>,
as well, for convenience.

=cut

use base qw(Class::Tangram);

our $fields =
    {
     int => {
	     max_age => { init_default => 1 },
	     hit_count => { init_default => 0 },
	    },
    };

our $abstract = 1;

=head1 METHODS

=over

=item get_request()

Returns a request if one is available, or undef if there are none.

=cut

sub get_request {
    my $self = shift;

    return undef
	if ( $self->{hit_count}++ >= $self->{max_age} );

    # Don't know how to return generic requests, just return true
    return 1;

}

=item stale()

Returns true if this acceptor has seen its day.

=cut

sub stale {
    my $self = shift;
    return ( $self->{hit_count} >= $self->{max_age} );
}

1;

__END__

=back

=head1 SEE ALSO

L<PSA>, L<PSA::Acceptor::AutoCGI>, L<PSA::Acceptor::Dummy>

=cut
