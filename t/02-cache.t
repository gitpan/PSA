#!/usr/bin/perl -w

use Test::More tests => 26;

use strict;
use lib "lib";

use_ok("PSA::Cache");

# Test the PSA compiled page Cache
my $cache;
eval { $cache = PSA::Cache->new; };
like($@, qr/missing.*required.*base_dir/i, "PSA::Cache needs a base dir");

$cache = PSA::Cache->new(base_dir => "t/templates");
is(ref($cache), "PSA::Cache", "PSA::Cache->new()");

# executable
ok($cache->executable("error-template1.pl"), "cache->executable(): +x");
ok(!$cache->executable("error-template2.pl"), "cache->executable(): -x");
ok(!$cache->executable("error-tmeplate1.pl"), "cache->executable(): missing");

# add a perl script to the cache
$cache->add_script("error-template1.pl");
is(ref $cache->{page}->{"error-template1.pl"}, "PSA::Cache::Entry",
   "\$cache->add_script");

# the cache doesn't catch errors for you
eval {
    $cache->run("error-template1.pl");
};
like($@, qr{^syntax error at .*t/templates/error-template1.pl line 3}m,
     "Errors caught and reported correctly");

# test PSA::Cache->type
is($cache->type("testdir/index.pl"), "Perl", "\$cache->type(file)");
is($cache->type("testdir/"), "Perl", "\$cache->type('dir/' w/index)");
is($cache->type("testdir"), "Perl", "\$cache->type('dir' w/index)");
is($cache->type("testdir2"), undef, "\$cache->type('dir' w/o index)");

is_deeply([ $cache->glob("testdir/*.pl") ],
	  [ qw(testdir/foobar.pl testdir/index.pl) ],
	  "\$cache->glob('testdir/*.pl')");

# test index, auto-loading of pages and that the return from functions
# gets returned properly
is($cache->run("testdir/index.pl"), "Hello, index",
   "Index pages loaded correctly");
ok(!$cache->executable("testdir/foobar.pl"),
   "cache->executable(): not executable w/index");
is($cache->run("testdir/foobar.pl"), "foobar",
   "cache->run(): not executable test");

# test the cache dirtying code
link("t/templates/testdir/index.pl", "t/templates/testdir/index1.pl");
ok(scalar(stat("t/templates/testdir/index1.pl")), "sanity test");
is($cache->run("testdir/index1.pl"), "Hello, index", "sanity test");
my $parent = $$;
if (my $pid = fork()) {
    #sleep 1;
    select(undef,undef,undef,0.25);
    unlink("t/templates/testdir/index1.pl");
    is($cache->run("testdir/index1.pl"), "Hello, index",
       "files not stat()'ed too frequently");
    # setting this to "1" gives the occassional random test failure,
    # so wait an extra second.
    $cache->set_stat_age(2);
    $cache->flush_stat();
    my $one;
    eval {
	is($cache->run("testdir/index1.pl"), "Hello, index",
	   "files not stat()'ed too frequently, even after flush");
	$one = 1;
	sleep 3;
	is($cache->run("testdir/index1.pl"), "Hello, index",
	   "files not stat()'ed unless stat buffer is flushed");
    };
    if ($@) {
	fail("error; probably means over-zealous stat()'ing, or NFS "
	     ."FS w/o NTP");
	diag('$@ is: "'.$@.'"');
	fail("(skipping second test)") unless $one;
    }
    kill(15, $pid);
    wait();
} else {
    $SIG{'__DIE__'} = sub { };
    open STDERR, ">/dev/null";
    open STDOUT, ">&STDERR";
    chomp(my $systype = `uname -s`);
    if ($systype =~ m/Linux|FreeBSD/) {
	exec("strace -o /tmp/trace.$parent -p $parent") or kill 9, $$;
    } elsif ($systype =~ m/SunOS/) {
	exec("truss -o /tmp/trace.$parent -p $parent") or kill 9, $$;
    } else {
	diag("# Sorry, don't know how to trace system calls under "
	     .$systype);
    }
}
if ( -f "/tmp/trace.$parent") {
    select(undef,undef,undef,0.25);
    system("egrep '^[fl]?stat' /tmp/trace.$parent");
    #unlink("/tmp/trace.$parent");
    isnt($?, 0, "No strace/truss of a stat() going on");
} else {
 SKIP: {
    skip("strace/truss didn't work - skipping strace() test", 1);
}
}
$cache->flush_stat();
eval { $cache->run("testdir/index1.pl"); };
like($@, qr/index1.pl.*does not exist/, "Files eventually stat()'ed");

# test loading .psa files
use_ok("PSA::Cache::Entry::PSA");
is($cache->run("psatest.psa"), "foo", "\$cache->run(file.psa)");

# psa include directories
push @{ $cache->include_dirs }, "t/templates/testdir";
is($cache->run("foobar.pl"), "foobar", "psa-bin includes");
