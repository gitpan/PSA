
use constant DEBUG => 0;
use BNZMV::Session qw(open_session);

my $psa = shift;

BNZMV::Session::open_session($psa->storage, $psa);

if ( my $passwd = delete $psa->heap->{password} ) {
    $psa->heap->{profile} = $psa->session->user->load_profile
	($psa->config->{profiles}, $passwd);
}
