
my $psa = shift;

print "ok 4\n";

my $arg = shift;

print "not " unless ($arg and $arg eq "take that!");
print "ok 5\n";

$psa->yield("fourth");


