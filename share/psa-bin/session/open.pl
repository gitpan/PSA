
use CGI::Cookie;

my $psa = shift;
my $user = shift
    or die \"EFAIL";

my $password = shift;
my $is_super = shift;

my $storage = $psa->storage;

$storage->tx_start(),
    $psa->attach_session("BNZMV::Session")
    unless $psa->heap_open;

my $session = $psa->session;

print STDERR "Session is: $session\n";
eval {
$psa->heap->{profile} = $user->load_profile
    ($psa->config->{profiles}, $password)
	unless $user->regpassword;
};
if ($@) {
    print STDERR "ERROR LOADING PROFILE: $@\n";
    die \"EBADPROFILE";
}

$psa->heap->{super} = 1 if $is_super;

my $r_client = $storage->remote("BNZMV::Client");
my ($client) = $storage->select
    ( $r_client,
      ($r_client->{code} eq $user->client_code)
    );

$session->data->{client} = $client;

$session->set_user($user);

$psa->response->set_cookie
    (new CGI::Cookie( -name => "SID",
		      -value => $psa->sid,
		      -expires =>  '+1d',
		      -path    =>  '/',
		    ));
