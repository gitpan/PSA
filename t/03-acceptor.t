#!/usr/bin/perl -w

use strict;
use lib "lib";
use Test::More tests => 5;

use_ok("PSA::Acceptor::AutoCGI");

open STDIN, "</dev/null";
my %new_env = (
	       GATEWAY_INTERFACE => "CGI/1.1",
	       REQUEST_METHOD => "GET",
	       QUERY_STRING => "foo=bar&baz=frop",
	       SCRIPT_NAME => "/cgi-bin/arse.cgi",
	       HTTP_COOKIE => "SID=123456789abcdef",
	       SUCK_DUMMY => 1,
	      );

while ( my ($k, $v) = each %new_env ) { $ENV{$k} = $v; }

my $acceptor = PSA::Acceptor::AutoCGI->new();
isa_ok($acceptor, "PSA::Acceptor",
       "PSA::Acceptor::AutoCGI->new()");

my $request = $acceptor->get_request();

ok($acceptor->stale, "normal CGI acceptor stale after one request");
is(ref $request, "PSA::Request::CGI", "\$acceptor->get_request()");
is($request->sid, "123456789abcdef", "SID ok");

# hmm, now how can we test FastCGI functionality, short of writing a
# minimal FastCGI server?

