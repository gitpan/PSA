
my $psa = shift;

# setup this session...
print "ok 1\n";

$psa->yield("next", q(take this!));
