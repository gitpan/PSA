
use constant FLAT_RE => qr{^/(?:js|css|img)/
                            (?:[\w\-]+/)*          # Truly anal!
                            [\w\-]+.(js|css|png|jpg|gif)$}x;

use constant DEBUG => 0;

my $psa = shift;

my $filename = $psa->request->path();
my $eperm;

# eval block to catch errors, etc
eval {

    # just in case we end up serving a flat request
    if ( $filename =~ m{${\(FLAT_RE)}}o) {

	$psa->run("index.pl");
	push @{ $psa->{times} }, "index.pl: ".Scriptalicious::show_delta;

    } else {

	#$psa->storage->insert($psa->request);
	#$psa->storage->tx_start();

	#my $audit_top;
	#unless ($psa->config->{no_session}) {
	    #push @{ $psa->{times} }, "sess(L): ".Scriptalicious::show_delta;
	    #$audit_top = $psa->run("audit/top.pl") if $psa->heap->{user};
	#}

	my ($try, $path_info);

	print STDERR "whassap.pl: WHASSSSSSSSSSSSSSSSSSSAAAAAAAAAAAAAP!!!\n"
	    if DEBUG;
	print STDERR $psa->request->quickdump
	    if DEBUG > 1;
	print STDERR Class::Tangram::quickdump($psa->request->env)
	    if DEBUG > 2;
	print STDERR "whassap.pl: fn = $filename\n"
	    if DEBUG;

	#if ( $psa->sid ) {
	    #$psa->run("/session/resume.pl") or return;
	#}

	if ( $filename ) {
	    $filename =~ m{^(/[\w\-\.]*)*} or die "bad filename";

	    $filename =~ s/\.(?:fcgi|pl)$/\.pl/i;

	    my @path = grep !/^\.\.?$/, grep /\S/, #grep /^[\w\-\.]+$/,
		split m{/}, $filename;
	    print STDERR "whassap.pl: path is: [ @path ]\n"
		if DEBUG > 1;
	    my $idx;
	    while (1) {
		$try .= "/".shift(@path);
		print STDERR "whassap.pl: trying: $try\n"
		    if DEBUG > 1;
		last if $psa->cache->executable($try);
		if ( $psa->cache->lestat($try) and
		     $psa->cache->executable("$try/handler.pl") ) {
		    $try .= "/handler.pl";
		    last;
		}
		last unless @path;
	    }

	    print STDERR "whassap.pl: got: $try\n"
		if DEBUG > 1;

	    $path_info = join "",
		map { "/$_" } @path;
	} else {
	    $try = "/index.pl";
	}
	$filename =~ s/\.pl$/\.html/;

	if ( $psa->cache->executable($try) ) {
	    print STDERR "whassap.pl: running: $try with $path_info\n"
		if DEBUG;
	    $psa->run($try, $path_info);
	    push @{ $psa->{times} }, "page: ".Scriptalicious::show_delta;
	}
	elsif ( -f "templates$filename" ) {
	    print STDERR "whassap.pl: Issuing flat file - $filename\n"
		if DEBUG;
	    $psa->run("/index.pl", $filename);
	}
	elsif ( -d "templates$filename" ) {
	    if ( $filename =~ m{/$} ) {
		print STDERR "whassap.pl: directory via index.pl - ${filename}index.html\n"
		    if DEBUG;
		$psa->run("/index.pl", $filename."index.html");
	    }
	    else {
		print STDERR "whassap.pl: redirecting to directory of $filename\n"
		    if DEBUG;
		$psa->response->make_redirect
		    (uri => $psa->request->uri(absolute => 'self')."/");
	    }
	}
	else {
	    print STDERR "whassap.pl: 404 on $try\n"
		if DEBUG;
	    $eperm = 1;
	}

	if ( $psa->sid and !$psa->heap_open ) {
	    eval { $psa->run("/session/resume.pl") };
	    print STDERR "whassap.pl: ERROR ATTACHING SESSION - ${$@}\n"
		if $@;
	}
	if ( $psa->heap_open ) {
	    $psa->run("/session/suspend.pl");
	}
    }
};

    

if ( $@ ) {

    print STDERR "whassap: EXCEPTION IN PAGE: >-\n$@\n...\n";

    $psa->storage->tx_rollback(-1);

    # caught an exception - ugh
    $psa->response->set_header(-status => "500 Internal Error");
    $psa->response->set_template([Template => "err/500.tt",
				  {
				   error => $@
				  }]);

} elsif ( $eperm ) {

    # file not found or no execute permission
    $psa->response->set_header(-status => "404 Not Found");
    $psa->response->set_template([Template => "err/404.tt",
				 {
				  request_uri => $psa->request->filename(),
				  referrer => $psa->request->http_referer()
				 }]);

} elsif ( $psa->response->is_null ) {
    # no response - erp
    $psa->response->set_header(-status => "500 Internal Error");
    $psa->response->set_template([Template => "err/500.tt",
				 {
				  page => $psa->request->filename()
				 }]);

} else {
    # This request worked.  Cool.
}
