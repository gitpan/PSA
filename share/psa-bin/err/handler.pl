
my $psa = shift;
my $path_info = shift;

my $filename = $psa->request->filename;

my $template = "err/default.tt";

my $vars =
    {
     referrer => $psa->request->referer,
    };


if ( $filename =~ /(\d{3})/ ) {
    $template = "err/$1.tt";
}

$psa->response->set_template
    ([ Template => $template,
       $vars,
     ]);
