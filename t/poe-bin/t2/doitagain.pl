
my $psa = shift;

Test::More::pass($psa->heap->{name}.": got to doitagain");

$psa->yield("hitmeoncemore");

