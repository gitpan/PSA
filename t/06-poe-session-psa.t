#!/usr/bin/perl -w

use POE;
use strict;

eval "use POE::Session::PSA;";
if ($@) {
    print "# skip all - $@";
    exit(1);
}

print "1..7\n";

# Test using PSA pages for POE states

my $psp = # Pretty Silly Processor ?  :-)
    PSA::POE->new
    (
     cache => PSA::Cache->new(base_dir => "t/poe-bin"),
     entry_point => "t1/whassap.pl",
    );

$poe_kernel->run();
