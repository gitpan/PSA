#  -*- perl -*-

# test various types of PSA HTTP responses

use Test::More tests => 34;

BEGIN { use_ok("PSA::Response::HTTP") };

my $resp = PSA::Response::HTTP->new;
my $header = $resp->cgiheader;

like($header, qr{^HTTP/1.1 200 OK}, "HTTP response header");
like($header, qr{^Content-Type: text/html}m, "Default content type");
like($header, qr{^Pragma: no-cache}m, "Default dynamic content");
like($header, qr{^Expires: \w{3}.*GMT}m, "Expires: header");
like($header, qr{^Date: \w{3}.*GMT}m, "Date: header");

$resp = PSA::Response::HTTP->new();
$resp->set_static;
$header = $resp->cgiheader;

unlike($header, qr{^Pragma: no-cache}m, "Can serve static content");
# FIXME - test expires is in the future
# FIXME - test for Etags, Last-Modified:

$resp = PSA::Response::HTTP->new();
$resp->set_file("t/testimg.jpg");
$header = $resp->cgiheader;

like($header, qr{^HTTP/1.1 200 OK}, "HTTP response header");
like($header, qr{^Content-Type: image/jpeg}m, "Magic content type");
like($header, qr{^Content-Length: 9616}m, "Magic content type");
like($header, qr{^Pragma: no-cache}m, "Default dynamic content");
unlike($header, qr{^Last-Modified: }m, "Files not auto-cached");

$resp->set_static;
$header = $resp->cgiheader;

unlike($header, qr{^Pragma: no-cache}m, "Can serve static content");
like($header, qr{^Last-Modified: }m, "Static content cachable");

$resp = PSA::Response::HTTP->new(file => "t/test.css", static => 1);
$header = $resp->cgiheader;

like($header, qr{^Last-Modified: }m,
     "Can pass static options to constructor");
like($header, qr{^Content-Type: text/css}m,
     "Magic file type detection avoided for known filename patterns");

open TEST, "+>t/test.out" or die $!;
select TEST;
$resp->issue();
seek TEST, 0, 0;
my $data = join "", <TEST>;

like($data, qr{^/\* Magic file type}m, "->issue() - file");

$resp = PSA::Response::HTTP->new(data => "Hello, world");

seek TEST, 0, 0;
$resp->issue();
truncate TEST, tell;
seek TEST, 0, 0;
$data = join "", <TEST>;

like($data, qr{^Hello, world}m, "->issue() - data");

$resp->set_template([ My1337Templat0r => "magic" ]);
seek TEST, 0, 0;
$resp->issue( My1337Templat0r => sub {
		  print "1337!\n";
		  pass("->issue() - templated responses");
		  is(shift, "magic", "->issue() - template data");
	      } );
truncate TEST, tell;
seek TEST, 0, 0;
$data = join "", <TEST>;

like($data, qr{^1337!}m, "Custom templating systems");

$resp = new PSA::Response::HTTP( nonfinal => 1, data => "Server Push");
seek TEST, 0, 0;
$resp->issue();
truncate TEST, tell;
seek TEST, 0, 0;
$data = join "", <TEST>;

like($data, qr{^Content-Type: multipart/x-mixed-replace}m,
     "Server Push");
like($data, qr{^--OOK}m, "MIME boundaries seen");
like($data, qr{^Content-Length: 11\b}m, "Part size sent");
like($data, qr{^Server Push}m, "Server Push content delivered");

$resp->set_data("Server Push This!");
seek TEST, 0, 0;
$resp->issue();
truncate TEST, tell;
seek TEST, 0, 0;
$data = join "", <TEST>;

unlike($data, qr{^HTTP}, "Server Push headers not sent twice");
like($data, qr{^Content-Length: 17\b}m,
     "length set on subsequent parts");
like($data, qr{^Server Push This!}m, "Server Push content delivered");

$resp->set_file("t/test.css");
seek TEST, 0, 0;
$resp->issue();
truncate TEST, tell;
seek TEST, 0, 0;
$data = join "", <TEST>;

like($data, qr{^Content-Type: text/css\b}m,
     "auto-content type on server push");
like($data, qr{^Content-Length: 105\b}m,
     "length detection");
like($data, qr{^/\* Magic file type}m,
     "Server Push file content delivered");

$resp = new PSA::Response::HTTP;
$resp->make_redirect("http://www.theregister.co.uk/");
seek TEST, 0, 0;
$resp->issue();
truncate TEST, tell;
seek TEST, 0, 0;
$data = join "", <TEST>;

like($data, qr{^HTTP/1.1 302 Found},
     "->make_redirect() - status Found");
like($data, qr{^Content-Length: 190\b}m,
     "Redirects contain RFC recommended HTML documents");
like($data, qr{^Location: http://}m,
     "->make_redirect() - Location header");

# FIXME - test sendfile extension (internal redirects)
