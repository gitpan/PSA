
my $psa = shift;
my $service = shift;

if ( !$service ) {
    my $path = $psa->request->uri->path;

    $service = ( $path =~ m{market} ? "market"
		 : ( $path =~ m{report.pl}
		     ? "customer"
		     : "yomomma" )
	       );
}


$psa->response->set_template
    ([ Template => "err/auth.html",
       {
	param => scalar($psa->request->get_param),
	service => $service,
       },
     ]);
