#!/usr/bin/perl -w

use strict;

use Test::More tests => 12;

use_ok("PSA::Config");

my $config = PSA::Config->new("t/testconf.yml");

is ($config->{acceptor}, "AutoCGI", "direct access works...");

# test Want lvalue accessors...
#my $value = $config->acceptor;
#is ($value, "AutoCGI", "get works");
#
#$config->acceptor = "PSA::Foo";
#
#is ($value = $config->acceptor, "PSA::Foo", "set works");
#
#is ($config->acceptor, "PSA::Foo", "set works");

{
local($SIG{__WARN__}) = sub { };
$config = PSA::Config->new("t/testconf_missing.yml");
}

is_deeply($config, (bless {}, "PSA::Config"),
	  "new with missing config doesn't die");

$config->{phase_rules} =
    { '.' => 'dev',
      '\0' => 'live',
    };

$ENV{SHUT_UP} = 1;

eval { $config->autoconf };
ok($@, "autoconf throws an error for bad config");

$config->{phases} = { dev => { foo => 'bar' } };

$config->autoconf;
is($config->{foo}, "bar", "autoconf copied in a scalar");
$config->{funny} = {};

$config->{phases} = { dev => { foo => { bar => "baz" },
			       funny => [ "little", "man" ],
			       bob => (bless { x => "Something" }, "Bob"),
			     } };

$config->autoconf;
is($config->{foo}{bar}, "baz", "autoconf copied in a hash over a scalar");
is_deeply($config->{funny}, [qw(little man)],
	  "autoconf copied in an array over a hash");
isa_ok($config->{bob}, "Bob", "bob");

$config->{phases} = { dev => { foo => { frop => "quux" },
			       funny => [ undef, undef, "come on!" ],
			       bob => (bless{ x => "Else" }, "Bert"),
			     } };

$config->autoconf;
is($config->{foo}{bar}, "baz", "autoconf didn't annihilate too much");
is($config->{foo}{frop}, "quux", "autoconf added to a hash");
is_deeply($config->{funny}, [ qw(little man), "come on!" ],
	  "autoconf added to an array");
isa_ok($config->{bob}, "Bert", "Bob turned into Bert");

