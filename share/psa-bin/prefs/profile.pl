
use YAML;

my $psa = shift;
$psa->run("auth/onlysuper.pl") or return;

my $new_profile = $psa->request->param("profile");

my $vars = { };

if ( $new_profile ) {
    eval {
	$psa->heap->{profile} = Load $new_profile;
    };
    if ( $@ ) {
	$vars->{profile} = $new_profile;
	$vars->{err} = $@;
    } else {
	$vars->{err} = "profile successfully updated.";
    }
}

$vars->{profile} ||= Dump $psa->heap->{profile};

$psa->response->set_template
    ([ Template => "prefs/profile.html",
       $vars ]);
