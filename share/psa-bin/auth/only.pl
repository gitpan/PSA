
my $psa = shift;
my $called_from = shift || "";

use constant DEBUG => 0;

eval {
    unless ( $psa->heap_open ) {
	if ( $psa->sid ) {
	    $psa->run("/session/resume.pl");
	} else {
	    print STDERR "/auth/only.pl - no SID\n";
	    die \"EACCESS";
	}
    }

    if ( $called_from and $called_from eq "onlysuper.pl" ) {
	die \"EINVAL" unless $psa->heap->{super};
    }

    $psa->heap->{auth_page} = 1;

};

if ( my $err =  $@ ) {
    print STDERR "auth/only.pl: BAD - $@\n" if DEBUG;
    return $psa->run("/auth/bad.pl", $err);
} elsif ( $called_from ne "passwd.pl"
	  and $psa->session->user->regpassword ) {
    $psa->response->make_redirect
	($psa->request->uri("absolute", "/prefs/passwd.pl"));
} elsif ( $called_from
	  and $called_from =~ m/^[A-Z]{6}$/
	  and !($psa->heap->{profile} and
		$psa->heap->{profile}->can_access($called_from)) ) {

    $psa->run("/auth/failed.pl", $called_from);
    return undef;

}  else {
    print STDERR "auth/only.pl: ok - ".$psa->session->user->username."\n"
	if DEBUG;
    return 1;
}

