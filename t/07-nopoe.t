#!/usr/bin/perl -w

use strict;
use PSA qw(Cache);

print "1..7\n";

# Test using PSA pages for POE states
my $psa = PSA->new(cache => PSA::Cache->new(base_dir => "t/poe-bin"));

$psa->run("t1/whassap.pl");

# only POE runs this state automatically
$psa->run("t1/_stop.pl");
