
use Scalar::Util qw(blessed);

my $psa = shift;

my @args = @_;

#print $psa->response->cgiheader;

if ( blessed $args[0] and $args[0]->isa("Exception") ) {
    $psa->run("issue/Template.pl", "rpc/error.html", { error  => $args[0] });
} else {
    print STDERR "RPC.pl: responding with : @args\n";
    $psa->run("issue/Template.pl", "rpc/respond.html", { objects => \@args } );
}
