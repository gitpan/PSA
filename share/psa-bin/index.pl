
my $psa = shift;

my $page = shift || "/index.html";

$page =~ s{^/}{};

$psa->response->set_template
    ([ Template => $page,
       {
	 url => $page,
       }
     ]);
