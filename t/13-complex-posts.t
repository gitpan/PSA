# -*- perl -*-

# 13, lucky for some.

use Test::More tests => 13;

BEGIN { use_ok("PSA::Request::CGI") }

# The first post is a normal get
my $env =
    {
     PATH_INFO => "/group/save.pl",
     SCRIPT_NAME => "bob",
     QUERY_STRING => "foo=bar&baz=frop",
    };

$ENV{SUCK_DUMMY}=1;

my $request = PSA::Request::CGI->fetch(env => $env);

use YAML;

is($request->param("foo"), "bar", "param()");

# now, a post

$env = Load <<YAML;
REQUEST_METHOD: 'POST'
PATH_INFO: '/fozzie-dev/group/save.pl'
HTTP_HOST: intranet.private.marketview.co.nz
HTTP_USER_AGENT: Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.6) Gecko/20040227 Firefox/0.8
HTTP_ACCEPT: text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,video/x-mng,image/png,image/jpeg,image/gif;q=0.2,*/*;q=0.1
HTTP_ACCEPT_LANGUAGE: en-us,en;q=0.5
HTTP_ACCEPT_ENCODING: gzip,deflate
HTTP_ACCEPT_CHARSET: ISO-8859-1,utf-8;q=0.7,*;q=0.7
HTTP_KEEP_ALIVE: 300
HTTP_CONNECTION: keep-alive
HTTP_REFERER: http://intranet.private.marketview.co.nz/fozzie-dev/group.pl?group=3
HTTP_COOKIE: SID=d60cbada78e5fea825f03d557ff75cb5; prefs=
CONTENT_TYPE: application/x-www-form-urlencoded
CONTENT_LENGTH: 200
YAML

open POST, "<t/13-postdata" or die $!;

#changed=key_words
#group=3
#name=LIQUORLAND+ANGUS+INN
#address=%22Cornwall+Sreet%22+%22Waterloo+Road%22+%22LOWER+HUTT%22+WELLINGTON%7E
#tla=46
#anzsic=5123
#key_words=%22ANGUS+INN+HOTEL%22*+%22ANGUS+INN%22*GET /fozzie-dev/group.pl?group=3

$request = PSA::Request::CGI->fetch(env => $env, fh => \*POST);

is(tell(POST), 0, "input not read yet");

is($request->param("tla"), 46, "POST param");

is($request->param("name"), "LIQUORLAND ANGUS INN", "spaces/url_decode");
is($request->param("key_words"),
   q{"ANGUS INN HOTEL"* "ANGUS INN"*},
   "spaces/url_decode");

$env = Load <<YAML;
HTTP_HOST: intranet.private.marketview.co.nz
HTTP_USER_AGENT: Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.6) Gecko/20040227 Firefox/0.8
HTTP_ACCEPT: text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,video/x-mng,image/png,image/jpeg,image/gif;q=0.2,*/*;q=0.1
HTTP_ACCEPT_LANGUAGE: en-us,en;q=0.5
HTTP_ACCEPT_ENCODING: gzip,deflate
HTTP_ACCEPT_CHARSET: ISO-8859-1,utf-8;q=0.7,*;q=0.7
HTTP_KEEP_ALIVE: 300
HTTP_CONNECTION: keep-alive
HTTP_REFERER: http://intranet.private.marketview.co.nz/fozzie-dev/test/file-upload.pl
HTTP_COOKIE: SID=6153d49844bff0d7449e75dce093e253; PHPSESSID=0630d6bc1495966cbb5db0cd385309d5; prefs=
REQUEST_METHOD: POST
CONTENT_TYPE: multipart/form-data; boundary=---------------------------1156053450463195201917059548
CONTENT_LENGTH: 4307
YAML

open POST, "<t/13-multipartdata" or die $!;
$request = PSA::Request::CGI->fetch(env => $env, fh => \*POST);

is($request->param("bob"), "a builder",
   "Multipart simple values");

isa_ok($request->param("file"), "PSA::Request::CGI::Upload",
       "Uploaded file");
is($request->param("file"), "spam.eml", "Works kind of like CGI");
like($request->param("file")->data, qr/spam/,
     "but is easier to retrieve data from");

$env = Load <<YAML;
HTTP_HOST: intranet.private.marketview.co.nz
HTTP_USER_AGENT: Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.6) Gecko/20040227 Firefox/0.8
HTTP_ACCEPT: text/xml,application/xml,application/xhtml+xml,text/html;q=0.9,text/plain;q=0.8,video/x-mng,image/png,image/jpeg,image/gif;q=0.2,*/*;q=0.1
HTTP_ACCEPT_LANGUAGE: en-us,en;q=0.5
HTTP_ACCEPT_ENCODING: gzip,deflate
HTTP_ACCEPT_CHARSET: ISO-8859-1,utf-8;q=0.7,*;q=0.7
HTTP_KEEP_ALIVE: 300
HTTP_CONNECTION: keep-alive
HTTP_REFERER: http://intranet.private.marketview.co.nz/fozzie-dev/test/file-upload.pl
HTTP_COOKIE: SID=6153d49844bff0d7449e75dce093e253; PHPSESSID=0630d6bc1495966cbb5db0cd385309d5; prefs=
REQUEST_METHOD: POST
CONTENT_TYPE: text/xml
YAML

open POST, "<t/13-xmldata" or die $!;
$request = PSA::Request::CGI->fetch(env => $env, fh => \*POST);

like($request->data, qr/stupid/i, "XML is stupid");
is($request->is_post, 1, "non-form posts are posts");
is($request->is_postfile, 1, "non-form posts are file posts");

close POST;
