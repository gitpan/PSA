
package PSA::Response;

=head1 NAME

PSA::Response - abstract request class

=head1 SYNOPSIS

 ...

=head1 DESCRIPTION

Sorry, this class isn't generic yet, due to lack of interest.  See
L<PSA::Response::HTTP> for the only concrete version of this class so
far.

=cut

use base qw(Class::Tangram);

our $schema
    = {
       fields => {
		 },
      };

1;
