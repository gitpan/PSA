
use constant DEBUG => 0;

my $psa = shift;

# when the session is suspended, unfortunately the heap gets removed
# from view, so save everything important in there elsewhere first.

if ( my $t = $psa->response->template ) {
    my $h;
    if ( ($h = $t->[2]) and ref $h eq "HASH" ) {
	$h->{user} = $psa->session->user
	    unless exists $h->{user};
	unless ( $psa->session->is_old ) {
	    $h->{auth_page} = delete $psa->heap->{auth_page}
		unless exists $h->{auth_page};
	    $h->{profile} = $psa->heap->{profile}
		unless exists $h->{profile};
	    $h->{client} = $psa->heap->{client}
		unless exists $h->{client};
	}
    }
}

#local($Tangram::TRACE) = \*STDERR;
if ( $psa->session->is_old ) {
    print STDERR "session/suspend.pl: ABORTING: ".$psa->session->quickdump
	if DEBUG;
    $psa->abort_session();
    $psa->storage->tx_rollback();
} else {
    print STDERR ("session/suspend.pl: suspending: ".$psa->session->quickdump,
		  "data: ".Class::Tangram::quickdump($psa->heap))
	if DEBUG;
    $psa->detach_session();
    $psa->storage->tx_commit();
}
print STDERR "session/suspend.pl: SID is now ".$psa->sid."\n"
    if DEBUG > 1;
