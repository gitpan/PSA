
my $psa = shift;

my ($wanted, $got, $old) = $psa->request->param(qw(pass confirm oldpasswd));

my $user = $psa->session->user;

my $error;
unless ( $user->regpassword or $user->auth_ok($old) ) {
    $error = "badpass";
}

if ( !$error and $wanted ne $got ) {
    $error = "mismatch";
}

if ( !$error ) {
    $user->set_password($got);
    $psa->storage->update($user);

    if ( !$psa->heap->{profile} ) {
	$psa->heap->{password} = $got;
    }
}

$psa->response->set_template
    ([ Template => "prefs/checkpasswd.html",
       {
	error => $error,
	success => !$error
       } ]),
