
my $psa = shift;
my $error_code = (shift) || \"EACCESS";

our %errors;

BEGIN {
%errors =
    ( "EACCESS" => ("You need to be an authorised user of the site "
		    ."before accessing this content"),
      "ENOSID" => ("No valid authentication token was found in your "
		   ."request.  Please log in."),
      "EBADSID" => ("An incorrect or very old authentication token "
		    ."was found in your request.  Please try logging "
		    ."in again."),
      "ENOUSER" => ("You session does not have a valid log-in "
		    ."associated with it.  Please log in."),
      "EBADPROFILE" => ("Your account is disabled, has expired, or "
			."there was a problem verifying your service "
			."subscription."),
      "EOLDSESSION" => ("You session has timed out due to inactivity."
			." Please re-enter your password to continue."
		       ),
      "EBADCHAR" => "Bad characters in log-in name",
      "EFAIL" => ("That username / password combination was not "
		  ."recognised.  Please try again."),
      "EFAULT" => "An internal error occurred",
      "EINVAL" => "Go away!  This page is not for you!",
    );
}

print STDERR "bad.pl - unknown exception: $error_code\n",
($error_code = \"EFAULT") unless ref $error_code;

my $error = $errors{$$error_code};

print STDERR "auth/bad.pl: $$error_code ($error)\n";

my $self_uri = $psa->request->get_uri;
print STDERR "auth/bad.pl: this is $self_uri\n";

my $next_uri = $psa->request->param("failed")
    || $psa->request->param("next")
    || $self_uri->path . ($self_uri->query ? "?" . $self_uri->query : "");

$psa->response->set_template
    ([ Template => "login.html",
       {
	next => $next_uri,
	( ($psa->heap_open && $psa->session->user)
	  ? ( q => { ssl => ($psa->request->uri->scheme eq "https"),
		     u => $psa->session->user->username              })
	  : ( q => scalar($psa->request->get_param) )
	),
	err => $$error_code,
	user => undef,
	error => $error,
       }, ]);

if ($psa->heap_open) {
    $psa->abort_session;
    $psa->storage->tx_rollback();
    unless ($$error_code eq "EOLDSESSION") {
	$psa->set_sid(undef)
    }
}

$psa->response->set_header(Status => 401);

if ( $psa->request->cookie_sid and $$error_code ne "EOLDSESSION" ) {
    $psa->response->set_cookie
	(new CGI::Cookie( -name => "SID",
			  -value => "",
			  -expires =>  '-1m',
			  -path    =>  '/',
			));
}

return undef;

