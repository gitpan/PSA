
my $psa = shift;

use Date::Manip qw(ParseDate);

if ( $psa->sid ) {
    eval { $psa->run("/session/resume.pl") };
}

$psa->run("/session/close.pl");

if ( my $where = $psa->request->param("back") ) {
    $psa->response->make_redirect
	($psa->request->uri(absolute => query => $where) . "loggedout=1");
}

$psa->response->set_template
    ([ Template => "logout.html",
       {
	user => undef,
       } ]);
