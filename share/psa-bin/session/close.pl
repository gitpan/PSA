
my $psa = shift;
use Date::Manip qw(ParseDate);

if ( $psa->heap_open ) {
    local($Tangram::TRACE)=\*STDERR;
    $psa->session->set_logged_out(ParseDate("now"));
    print STDERR "/session/close.pl: detaching ".$psa->session->quickdump;
    $psa->detach_heap();
    $psa->storage->tx_commit();

    $psa->set_sid(undef);
}

$psa->response->set_cookie
    (new CGI::Cookie( -name => "SID",
		      -value => "",
		      -expires =>  '-1m',
		      -path    =>  '/',
		    ));
