
my $psa = shift;
my $args = shift;

$psa->run("auth/only.pl", "passwd.pl") or return;

print STDERR "Request: ".Data::Dumper::Dumper(scalar $psa->request->get_param);

if ( $psa->request->param("chosen") ) {
    $psa->run("/prefs/promptpasswd.pl");
} elsif ( $psa->request->param("confirm") ) {
    $psa->run("/prefs/checkpasswd.pl");
} else {
    $psa->run("/prefs/genpasswd.pl", $args);
}


1;
