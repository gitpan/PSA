#!/usr/bin/perl -w

use strict;
use Test::More tests => 60;
use Data::Dumper;

#BEGIN { ( -d "lib" ) || chdir ("..");
	#( -d "lib" ) || die("where am i?"); }
#use lib "lib";
use lib "../lib";

use_ok 'PSA::Request::CGI';

# Emulate a CGI request
my %new_env = (
	       GATEWAY_INTERFACE => "CGI/1.1",
	       REQUEST_METHOD => "GET",
	       QUERY_STRING => "foo=bar&baz=frop",
	       SCRIPT_NAME => "/cgi-bin/arse.cgi",
	       HTTP_COOKIE => "SID=123456",
	      );
while ( my ($k, $v) = each %new_env ) { $ENV{$k} = $v; }

my $request = PSA::Request::CGI->fetch();

# ->fetch();
ok($request->isa("PSA::Request::CGI"),
   "PSA::Request::CGI->fetch() returns");

# ->param();
is($request->param, 2,
   "PSA::Request::CGI->param() returns current number of arguments");
is($request->param('foo'), "bar",
   "PSA::Request::CGI->param('foo') returns correct value");

is($request->cookies->{SID}, "123456",
   "PSA::Request::CGI->cookies->{SID} was set");

#custom env
my $sid = "12345678" x 4;  # that's the kind of SID an IDIOT would put
                           # on his SUITCASE!!!
my $env = {
	   GATEWAY_INTERFACE => "CGI/1.1",
	   REQUEST_METHOD => "GET",
	   QUERY_STRING => "baz=new&baz=new",
	   SCRIPT_NAME => "/cgi-bin/arse.cgi",
	   SERVER_NAME => "arse.com",
	   PATH_INFO => "/$sid/foo.pl",
	   };

# tests without cookies
$request = PSA::Request::CGI->fetch(env => {%$env});

is($request->uri("cheese.pl"), "../cheese.pl?SID=$sid",
   "Rel. URI gen. w/o cookie");
is($request->uri("/cheese.pl"), "../cheese.pl?SID=$sid",
   "Rel. URI gen. w/o cookie [leading /]");

is($request->uri(query => "cheese.pl"), "../cheese.pl?SID=$sid&",
   "Rel. URI gen. [QUERY] w/o cookie");
is($request->uri(query => "/cheese.pl"), "../cheese.pl?SID=$sid&",
   "Rel. URI gen. [QUERY] w/o cookie [leading /]");

is($request->uri(post => "cheese.pl"), "cheese.pl",
   "Rel. URI gen. [POST] w/o cookie");
is($request->uri(post => "/cheese.pl"), "cheese.pl",
   "Rel. URI gen. [POST] w/o cookie [leading /]");

is($request->uri(absolute => "cheese.pl"),
   "http://arse.com/cgi-bin/arse.cgi/cheese.pl?SID=$sid",
   "Abs. URI gen. w/o cookie");
is($request->uri(absolute => "/cheese.pl"),
   "http://arse.com/cgi-bin/arse.cgi/cheese.pl?SID=$sid",
   "Abs. URI gen. w/o cookie [leading /]");

is($request->uri(post => absolute => "cheese.pl"),
   "http://arse.com/cgi-bin/arse.cgi/$sid/cheese.pl",
   "Abs. URI gen. [POST] w/o cookie");
is($request->uri(post => absolute => "/cheese.pl"),
   "http://arse.com/cgi-bin/arse.cgi/$sid/cheese.pl",
   "Abs. URI gen. [POST] w/o cookie [leading /]");

# tests with cookies
$env->{HTTP_COOKIE} = "SID=$sid";
$request = PSA::Request::CGI->fetch(env => {%$env});

#kill 2, $$;
is($request->uri("cheese.pl"), "../cheese.pl",
   "Rel. URI gen. w/cookie");
is($request->uri("/cheese.pl"), "../cheese.pl",
   "Rel. URI gen. w/cookie [leading /]");

is($request->uri(query => "cheese.pl"), "../cheese.pl?",
   "Rel. URI gen. [QUERY] w/cookie");
is($request->uri(query => "/cheese.pl"), "../cheese.pl?",
   "Rel. URI gen. [QUERY] w/cookie [leading /]");

is($request->uri(absolute => "cheese.pl"),
   "http://arse.com/cgi-bin/arse.cgi/cheese.pl",
   "Abs. URI gen. w/cookie");
is($request->uri(absolute => "/cheese.pl"),
   "http://arse.com/cgi-bin/arse.cgi/cheese.pl",
   "Abs. URI gen. w/cookie [leading /]");

# tests with INVALID cookies
$env->{HTTP_COOKIE} = "SID=b00bfaceb00bfaceb00bfaceb00bface";
$request = PSA::Request::CGI->fetch(env => {%$env});

is($request->uri("cheese.pl"), "../cheese.pl?SID=$sid",
   "Rel. URI gen. w/BAD cookie");
is($request->uri("/cheese.pl"), "../cheese.pl?SID=$sid",
   "Rel. URI gen. w/BAD cookie [leading /]");

is($request->uri(post => "cheese.pl"), "cheese.pl",
   "Rel. URI gen. [POST] w/BAD cookie");
is($request->uri(post => "/cheese.pl"), "cheese.pl",
   "Rel. URI gen. [POST] w/BAD cookie [leading /]");

is($request->uri(absolute => "cheese.pl"),
   "http://arse.com/cgi-bin/arse.cgi/cheese.pl?SID=$sid",
   "Abs. URI gen. w/BAD cookie");
is($request->uri(absolute => "/cheese.pl"),
   "http://arse.com/cgi-bin/arse.cgi/cheese.pl?SID=$sid",
   "Abs. URI gen. w/BAD cookie [leading /]");

is($request->uri(post => absolute => "cheese.pl"),
   "http://arse.com/cgi-bin/arse.cgi/$sid/cheese.pl",
   "Abs. URI gen. [POST] w/BAD cookie");
is($request->uri(post => absolute => "/cheese.pl"),
   "http://arse.com/cgi-bin/arse.cgi/$sid/cheese.pl",
   "Abs. URI gen. [POST] w/BAD cookie [leading /]");

# tests with no path_info
$env->{PATH_INFO} = "";
$env->{HTTP_COOKIE} = "";
$request = PSA::Request::CGI->fetch(env => {%$env});
$request->set_sid($sid);

is($request->uri("cheese.pl"), "arse.cgi/cheese.pl?SID=$sid",
   "Rel. URI gen. w/o cookie or path_info");
is($request->uri("/cheese.pl"), "arse.cgi/cheese.pl?SID=$sid",
   "Rel. URI gen. w/o cookie or path_info [leading /]");

is($request->uri(post => "cheese.pl"), "arse.cgi/$sid/cheese.pl",
   "Rel. URI gen. [POST] w/o cookie or path_info");
is($request->uri(post => "/cheese.pl"), "arse.cgi/$sid/cheese.pl",
   "Rel. URI gen. [POST] w/o cookie or path_info [leading /]");

is($request->uri(absolute => "cheese.pl"),
   "http://arse.com/cgi-bin/arse.cgi/cheese.pl?SID=$sid",
   "Abs. URI gen. w/o cookie or path_info");
is($request->uri(absolute => "/cheese.pl"),
   "http://arse.com/cgi-bin/arse.cgi/cheese.pl?SID=$sid",
   "Abs. URI gen. w/o cookie or path_info [leading /]");

is($request->uri(post => absolute => "cheese.pl"),
   "http://arse.com/cgi-bin/arse.cgi/$sid/cheese.pl",
   "Abs. URI gen. [POST] w/o cookie or path_info");
is($request->uri(post => absolute => "/cheese.pl"),
   "http://arse.com/cgi-bin/arse.cgi/$sid/cheese.pl",
   "Abs. URI gen. [POST] w/o cookie or path_info [leading /]");

$env = {
	   GATEWAY_INTERFACE => "CGI/1.1",
	   REQUEST_METHOD => "GET",
	   QUERY_STRING => "baz=new&baz=new",
	   SCRIPT_NAME => "/psa/index.cgi",
	   SERVER_NAME => "arse.com",
	   PATH_INFO => "/schema/add_class.psa",
	   };
$env->{HTTP_COOKIE} = "SID=12345123451234512345123451234512";
$request = PSA::Request::CGI->fetch(env => $env);

is ($request->uri( query => "create_class.psa" ),
	"create_class.psa?",
	"Rel. URI gen. w/cookie & subdir in PATH_INFO" );
is ($request->uri( query => "/create_class.psa" ),
	"../create_class.psa?",
	"Rel. URI gen. w/cookie & subdir in PATH_INFO [leading /]" );

is ($request->uri( query => "app/create_class.psa" ),
	"app/create_class.psa?",
	"Rel. URI gen. w/cookie & subdir in PATH_INFO" );
is ($request->uri( query => "/app/create_class.psa" ),
	"../app/create_class.psa?",
	"Rel. URI gen. w/cookie & subdir in PATH_INFO [leading /]" );

# test new bug

$env = {
	DOCUMENT_ROOT => "/home/sv/pkgsrc/psa-liveman",
	FCGI_ROLE => "RESPONDER",
	GATEWAY_INTERFACE => "CGI/1.1",
	HTTP_HOST => "psatest",
	PATH => "/bin:/usr/bin:/sbin:/usr/sbin",
	PATH_INFO => "/dumpenv.pl",
	QUERY_STRING => "",
	REMOTE_ADDR => "192.168.69.42",
	REMOTE_PORT => "32928",
	REQUEST_METHOD => "GET",
	REQUEST_URI => "/dumpenv.pl",
	SCRIPT_FILENAME => "/var/www/index.cgi",
	SCRIPT_NAME => "",
	SCRIPT_URI => "http://psatest/dumpenv.pl",
	SCRIPT_URL => "/dumpenv.pl",
	SERVER_ADDR => "192.168.69.42",
	SERVER_NAME => "psatest",
	SERVER_PORT => "80",
	SERVER_PROTOCOL => "HTTP/1.1",
	SERVER_SIGNATURE => "",
       };
$env->{HTTP_COOKIE} = "SID=12345123451234512345123451234512";

$request = PSA::Request::CGI->fetch(env => $env);

is ($request->uri( absolute => 'self' ),
    "http://psatest/dumpenv.pl",
    "No CGI script name");

# test `flat' URIs
is ($request->uri( absolute => flat => "images/foo.png" ),
    "http://psatest/images/foo.png",
    "flat + absolute (root)");
is ($request->uri( absolute => flat => "/images/foo.png" ),
    "http://psatest/images/foo.png",
    "flat + absolute (root) [leading /]");

is ($request->uri( flat => "images/foo.png" ),
    "images/foo.png",
    "flat + relative (root)");
is ($request->uri( flat => "/images/foo.png" ),
    "images/foo.png",
    "flat + relative (root) [leading /]");

$env->{PATH_INFO} = "/foobar/dumpenv.pl";
$request = PSA::Request::CGI->fetch(env => $env);
is ($request->uri( absolute => 'self' ),
    "http://psatest/foobar/dumpenv.pl",
    "Sanity check");

is ($request->uri( absolute => flat => "images/foo.png" ),
    "http://psatest/images/foo.png",
    "flat + absolute (offset from root)");
is ($request->uri( absolute => flat => "/images/foo.png" ),
    "http://psatest/images/foo.png",
    "flat + absolute (offset from root) [leading /]");

is ($request->uri( flat => "images/foo.png" ),
    "../images/foo.png",
    "flat + relative (offset from root)");
is ($request->uri( flat => "/images/foo.png" ),
    "../images/foo.png",
    "flat + relative (offset from root) [leading /]");


$env = {split / = |\n/, <<'ENV'};
DOCUMENT_ROOT = /var/www/dev/psa-liverez
GATEWAY_INTERFACE = CGI/1.1
PATH_INFO = /dumpenv.pl
PATH_TRANSLATED = /var/www/index.cgi/dumpenv.pl
QUERY_STRING = 
REMOTE_ADDR = 192.168.69.42
REMOTE_PORT = 51367
REQUEST_METHOD = GET
REQUEST_URI = /dumpenv.pl
SCRIPT_FILENAME = /var/www/index.cgi
SCRIPT_NAME = 
SCRIPT_URI = http://somehost.com/dumpenv.pl
SCRIPT_URL = /dumpenv.pl
SERVER_ADDR = 192.168.69.42
SERVER_NAME = somehost.com
SERVER_PORT = 80
SERVER_PROTOCOL = HTTP/1.1
ENV

$request = PSA::Request::CGI->fetch(env => $env);
is ($request->uri( post => absolute => 'self' ),
    "http://somehost.com/dumpenv.pl",
    "post => absolute => self");
is ($request->uri( post => 'self' ),
    "dumpenv.pl",
    "post => self");

#---------------------------------------------------------------------
#  Tests for LiteSpeed intepretation of CGI specification :)
$env = {split / = |\n/, <<'ENV'};
DOCUMENT_ROOT = /var/www/
FCGI_ROLE = RESPONDER
GATEWAY_INTERFACE = CGI/1.1
HTTP_HOST = squirt.vilain.net
QUERY_STRING = 
REMOTE_ADDR = 192.168.69.42
REMOTE_PORT = 36626
REQUEST_METHOD = GET
REQUEST_URI = /dumpenv.pl
SCRIPT_NAME = /dumpenv.pl
SERVER_NAME = squirt.vilain.net
SERVER_PORT = 80
SERVER_PROTOCOL = HTTP/1.1
SERVER_SOFTWARE = LiteSpeed/1.2.2 Standard
ENV

$request = PSA::Request::CGI->fetch(env => $env);
is ($request->uri( post => absolute => 'self' ),
    "http://squirt.vilain.net/dumpenv.pl",
    "(no PATH_INFO) post => absolute => self");
is ($request->uri( post => 'self' ),
    "dumpenv.pl",
    "(no PATH_INFO) post => self");

#---------------------------------------------------------------------
#  Ugh.  Look at these two requests.  They were obtained via the same
#  gateway.  One has the SCRIPT_NAME set to a valid value, the other
#  doesn't.

#  Apache sucks.

use YAML;

$env = Load <<'YAML';
  DOCUMENT_ROOT: '/mv/app/dev/bnz/html'
  FCGI_ROLE: RESPONDER
  GATEWAY_INTERFACE: CGI/1.1
  HTTP_ACCEPT: ! >-
    text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,video/x-mng,image/png,image/jpeg,image/gif;q=0.2,*/*;q=0.1
  HTTP_ACCEPT_CHARSET: ISO-8859-1,utf-8;q=0.7,*;q=0.7
  HTTP_ACCEPT_ENCODING: gzip,deflate
  HTTP_ACCEPT_LANGUAGE: en-us,en;q=0.5
  HTTP_CONNECTION: keep-alive
  HTTP_COOKIE: mv_https=no
  HTTP_HOST: bnzdev.private.marketview.co.nz
  HTTP_KEEP_ALIVE: 300
  HTTP_USER_AGENT: |-
    Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.6) Gecko/20040227 Firefox/0.8
  PATH: >-
    /home/samv/bin:/mv/local/bin:/usr/local/bin:/usr/bin:/bin:/usr/bin/X11:/usr/games:/usr/local/sbin:/usr/sbin:/sbin
  QUERY_STRING: ''
  REMOTE_ADDR: 192.168.1.30
  REMOTE_PORT: 36464
  REQUEST_METHOD: GET
  REQUEST_URI: '/fozzie'
  SCRIPT_FILENAME: '/mv/app/dev/bnz/html/fozzie'
  SCRIPT_NAME: '/fozzie'
  SCRIPT_URI: http://bnzdev.private.marketview.co.nz/fozzie
  SCRIPT_URL: '/fozzie'
  SERVER_ADDR: 192.168.1.14
  SERVER_ADMIN: service@marketview.co.nz
  SERVER_NAME: bnzdev.private.marketview.co.nz
  SERVER_PORT: 80
  SERVER_PROTOCOL: HTTP/1.1
  SERVER_SIGNATURE: >
    <ADDRESS>Apache/1.3.29 Server at bnzdev.private.marketview.co.nz Port
    80</ADDRESS>
  SERVER_SOFTWARE: Apache
YAML

$request = PSA::Request::CGI->fetch(env => $env);
$request->set_sid("bfffd0ff72b3be5c4bd4154dc404c3f7");
$request->set_base("/fozzie");

is ($request->uri( absolute => post => '/main.pl' ),
    "http://bnzdev.private.marketview.co.nz/fozzie/bfffd0ff72b3be5c4bd4154dc404c3f7/main.pl",
    "(no PATH_INFO II) post => self [absolute]");

is ($request->uri( post => '/main.pl' ),
    "fozzie/bfffd0ff72b3be5c4bd4154dc404c3f7/main.pl",
    "(no PATH_INFO II) post => self");

$env = Load <<'YAML';
  DOCUMENT_ROOT: '/mv/app/dev/bnz/html'
  FCGI_ROLE: RESPONDER
  GATEWAY_INTERFACE: CGI/1.1
  HTTP_ACCEPT: ! >-
    text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,video/x-mng,image/png,image/jpeg,image/gif;q=0.2,*/*;q=0.1
  HTTP_ACCEPT_CHARSET: ISO-8859-1,utf-8;q=0.7,*;q=0.7
  HTTP_ACCEPT_ENCODING: gzip,deflate
  HTTP_ACCEPT_LANGUAGE: en-us,en;q=0.5
  HTTP_CACHE_CONTROL: max-age=0
  HTTP_CONNECTION: keep-alive
  HTTP_COOKIE: SID=ab63bbb427afff99a2f37c0bfacb658a
  HTTP_HOST: bnzdev.private.marketview.co.nz
  HTTP_KEEP_ALIVE: 300
  HTTP_USER_AGENT: |-
    Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.6) Gecko/20040227 Firefox/0.8
  PATH: >-
    /home/samv/bin:/mv/local/bin:/usr/local/bin:/usr/bin:/bin:/usr/bin/X11:/usr/games:/usr/local/sbin:/usr/sbin:/sbin
  PATH_INFO: '/ab63bbb427afff99a2f37c0bfacb658a/login.pl'
  PATH_TRANSLATED: |-
    /mv/app/dev/bnz/html/ab63bbb427afff99a2f37c0bfacb658a/login.pl
  QUERY_STRING: 'foo=bar&baz=frop'
  REMOTE_ADDR: 192.168.1.30
  REMOTE_PORT: 36484
  REQUEST_METHOD: GET
  REQUEST_URI: '/fozzie/ab63bbb427afff99a2f37c0bfacb658a/login.pl'
  SCRIPT_FILENAME: '/mv/app/dev/bnz/html/fozzie'
  SCRIPT_NAME: '/fozzie'
  SCRIPT_URI: ! >-
    http://bnzdev.private.marketview.co.nz/fozzie/ab63bbb427afff99a2f37c0bfacb658a/login.pl
  SCRIPT_URL: '/fozzie/ab63bbb427afff99a2f37c0bfacb658a/login.pl'
  SERVER_ADDR: 192.168.1.14
  SERVER_ADMIN: service@marketview.co.nz
  SERVER_NAME: bnzdev.private.marketview.co.nz
  SERVER_PORT: 80
  SERVER_PROTOCOL: HTTP/1.1
  SERVER_SIGNATURE: >
    <ADDRESS>Apache/1.3.29 Server at bnzdev.private.marketview.co.nz Port
    80</ADDRESS>
  SERVER_SOFTWARE: Apache
YAML

$request = PSA::Request::CGI->fetch(env => $env);

is ($request->uri( absolute => post => 'self' ),
    "http://bnzdev.private.marketview.co.nz/fozzie/login.pl",
    "(no PATH_INFO III) post => self [absolute]");

is ($request->uri( post => 'self' ),
    "../login.pl",
    "(no PATH_INFO III) post => self");

#BUG - uris are now getting query strings appended!

is ($request->uri( flat => '/some/file' ),
    "../../some/file",
    "(no PATH_INFO III) flat");


