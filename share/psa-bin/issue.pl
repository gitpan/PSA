
# This page is responsible for issuing responses.
my $psa = shift;

my $fh = select $psa->acceptor->output_fd;

# check for a template response
if (my $template = $psa->response->template) {

    ref($template) eq "ARRAY"
	or die("Page filled response template with $template, "
	       ."expecting array ref");

    my $method = $template->[0];

    $psa->run("issue/$method.pl", @{$template}[1..$#$template]);

} else {

    # not a template response - just issue it
    $psa->response->issue();

}

$psa->acceptor->flush;

select $fh;

