
my $psa = shift;

my $chosen = $psa->request->param("chosen");

my ($random, $custom) = $psa->request->param(qw(passwd0 passwd1));

my $passwd;
if ( $chosen eq "random" ) {
    $passwd = $random;
} elsif ( $chosen eq "custom" &&
	  $custom &&
	  (length($custom) >= 6) &&
	  ($custom =~ m/[A-Z].*\d|\d.*[A-Z]/i)) {
    $passwd = $custom
} else {
    return $psa->run("/prefs/genpasswd.pl", { badpasswd => 1 });
}

$psa->response->set_template
    ([ Template => "prefs/promptpasswd.html",
       {
	pass => $passwd,
       } ]);
