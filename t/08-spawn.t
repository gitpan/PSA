#!/usr/bin/perl -w

# this test tests both PSA and POE versions of `spawn', which are a
# bit like POE's POE::Session::Create.

BEGIN {
    eval { require POE };
    if ( $@ ) {
	eval q{use Test::More skip_all => "POE not installed"};
	exit;
    }
}

use Test::More tests => 16;
use PSA qw(Cache Heap);
use POE qw(Session::PSA);

# Test using PSA pages for POE states
my $psa = PSA->new(cache => PSA::Cache->new(base_dir => "t/poe-bin"));
$psa->attach_heap;
$psa->heap->{name} = "non-poe manager";
$psa->run("t2/whassap.pl");

# Test using PSA pages for POE states

my $poe = PSA::POE->new
    (
     cache => $psa->cache,
     entry_point  => "t2/whassap",
    );
$poe->attach_heap;
$poe->heap->{name} = "poe manager";

$poe_kernel->run();
