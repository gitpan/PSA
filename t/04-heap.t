#!/usr/bin/perl -w

use strict;
use lib "lib";
use Test::More tests => 22;

use Storable qw(dclone);
use PSA;
use_ok("PSA::Heap");

my $psa = new PSA();
my $heap = new PSA::Heap($psa);

my $sid = $psa->sid;
ok($sid, "Session ID of $sid");

is(ref $heap, "PSA::Heap", "PSA::Heap->new()");
like(tied(%{$heap->session_h}), qr/Apache::Session::File/,
   "Ties to Apache::Session::File");

my $rand_val = rand(42*69);
$psa->heap->{test} = $rand_val;

$heap->flush();

isnt(ref $psa->heap, "HASH", "heap not left behind after flush");

# re-attach heap
$heap = PSA::Heap->new($psa);
is(ref $psa->heap, "HASH", "heap easily re-picked up");
is($psa->heap->{test}, $rand_val, "Got the same heap back");
is($psa->heap_obj->hits, 2, "hit count increases");

$heap->flush();

# now mix Storage and heap; set up a little object that behaves like
# Storage first
my @objects;
my $psuedo_storage =
    bless {
	   objects => Set::Object->new
	   (
	    @objects = ( (bless [ qw(foo bar) ], "This"),
			 (bless [ qw(this that) ], "Other"),
			 (bless [ qw(other baz) ], "Foo"),
			 (bless [ qw(quux frob) ], "Bar") ),
	   ),
	  }, "Psuedo::Storage";

sub Psuedo::Storage::id {
    my $self = shift;
    my $what = shift;
    if ($self->{objects}->includes($what)) {
	return (join "", map { sprintf "%.3d", $_ }
		unpack("C*", ref $what));
    } else {
	return undef;
    }
}

my $load_count = 0;
sub Psuedo::Storage::load {
    my $self = shift;
    my $type = join("", pack("C*", (shift=~m/(\d{3})/g)));
    #diag("`Loading' object of type $type");
    $load_count++;
    return ( grep { $type eq ref $_ } $self->{objects}->members )[0];
}

# Then, attach the heap again, and insert a structure with some
# `persistent' objects
$psa->attach_heap();
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

# Flatten it
$psa->heap_obj->flatten($psuedo_storage);

is_deeply($psa->heap->{test_structure},
	  [
	   'some', 'normal data',
	   'more', { 'complex' => [ 'data', 'with', 'lots', 'of',
				    \'references' ] },
	   'simple',
	   bless( do{\(my $o = '084104105115')},
                  'PSA::Heap::Memento' ),
	  'arrayref', [ 'should', 'work', 'just', 'testing',
		       bless( do{\(my $o = '079116104101114')},
		              'PSA::Heap::Memento' ) ],
          'hashref', { 'yeah' => bless( do{\(my $o = '070111111')},
		                        'PSA::Heap::Memento' ) },
          'refref', \bless( do{\(my $o = '066097114')},
	                    'PSA::Heap::Memento' )
     ], "Flattened OK");

use Data::Dumper;
#print Dumper $psa->heap;

# reload it
$psa->detach_heap();
$psa->attach_heap();

is($psa->sid, $sid, "Sid remained the same after flush");
is($psa->heap_obj->hits, 4, "hit count increases");
$psa->heap_obj->unflatten($psuedo_storage);

is($load_count, 0, "Load hasn't happened yet");
isnt($psa->heap->{test_structure}, $old_struct, "Sanity test");
is_deeply(${ $psa->heap->{test_structure}->[11] },
	  ${ $struct_copy->[11] },
	  "Seems to be the same structure");
is($load_count, 1, "Objects loaded on demand");
is_deeply($psa->heap->{test_structure}, $struct_copy,
	  "Heap was reconstituted successfully");
is($load_count, 4, "Objects loaded on demand");
$psa->detach_heap();

# now test commit_heap
$psa->attach_heap();
$psa->heap->{test} = 1;
$psa->commit_heap();

is_deeply(${ $psa->heap->{test_structure}->[11] },
	  ${ $struct_copy->[11] },
	  "Hasn't lost its structure");
is_deeply($psa->heap->{test_structure}, $struct_copy,
	  "Heap was reconstituted successfully");
is($psa->heap->{test}, 1, "Changes still there");
