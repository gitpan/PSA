#!/usr/bin/perl -w

use strict;

use Test::More tests => 3;

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
