#!/usr/bin/perl -w

use strict;
use lib "lib";

use Test::More tests => 20;

use Storable qw(dclone);
use PSA qw(Heap);
use_ok("PSA::Session");
use T2::Storage;

my $storage = T2::Storage->open("t/psatest");

#local($Tangram::TRACE) = \*STDERR;
my $psa = new PSA(storage => $storage);

$psa->attach_session();
my $sess = $psa->heap_obj;

my $sid = $psa->sid;
like($sid, qr/^[a-f0-9]{32}$/i, "Session ID of $sid");

is(ref $sess, "PSA::Session", "PSA::Session->new()");

my $rand_val = rand(42*69);
$psa->heap->{test} = $rand_val;

$psa->detach_heap;

isnt(ref $psa->heap, "HASH", "heap not left behind after flush");

# re-attach heap
is($psa->sid, $sid, "SID still intact");
$psa->attach_session;
is(ref $psa->heap, "HASH", "heap easily re-picked up");
is($psa->heap->{test}, $rand_val, "Got the same heap back");
is($psa->heap_obj->sid, $sid, "SID matches what we had");
is($psa->heap_obj->hits, 2, "hit count increases");

$psa->detach_heap;

my @objects =
    ( (bless [ qw(foo bar) ], "This"),
      (bless [ qw(this that) ], "Other"),
      (bless [ qw(other baz) ], "Foo"),
      (bless [ qw(quux frob) ], "Bar")
    );

# Then, attach the heap again, and insert a structure with some
# `persistent' objects
$psa->attach_session();
is($psa->sid, $sid, "Sid remained the same after flush");
is($psa->heap_obj->hits, 3, "hit count increases");
my $old_struct = $psa->heap->{test_structure} =
    [
     some => "normal data",
     more => { "complex" => [ qw(data with lots of), \"references" ] },
     simple => $objects[0],
     arrayref => [ qw(should work just testing), $objects[1], ],
     hashref => { yeah => $objects[2] },
     refref => \$objects[3],
    ];
my $struct_copy = dclone($old_struct);

# reload it
is($psa->sid, $sid, "Sid still OK");
$psa->detach_session();
is($psa->sid, $sid, "Sid remained the same after detach");
$sess = undef;
$psa->attach_session();
is($psa->sid, $sid, "Sid remained the same after attach");

is($psa->heap_obj->hits, 4, "hit count increases");
#$psa->heap_obj->unflatten($psuedo_storage);

#is($load_count, 0, "Load hasn't happened yet");
isnt($psa->heap->{test_structure}, $old_struct, "Sanity test");
is_deeply(${ $psa->heap->{test_structure}->[11] },
	  ${ $struct_copy->[11] },
	  "Seems to be the same structure");
#is($load_count, 1, "Objects loaded on demand");
#is_deeply($psa->heap->{test_structure}, $struct_copy,
	  #"Session was reconstituted successfully");
#is($load_count, 4, "Objects loaded on demand");
$psa->detach_heap();

# now test commit_heap
$psa->attach_session();
$psa->heap->{test} = 1;
$psa->commit_heap();

is_deeply(${ $psa->heap->{test_structure}->[11] },
	  ${ $struct_copy->[11] },
	  "Hasn't lost its structure");
is_deeply($psa->heap->{test_structure}, $struct_copy,
	  "Session was reconstituted successfully");
is($psa->heap->{test}, 1, "Changes still there");
