
my $psa = shift;

print "ok 2\n";

my $arg = shift;

print "not " unless ($arg and $arg eq "take this!");

print "ok 3\n";

$psa->run("t1/third.pl", "take that!");

