
my $psa = shift;

Test::More::pass($psa->heap->{name}.": got to doit");

$psa->yield("doitagain");
