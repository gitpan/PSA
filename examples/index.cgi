#!/usr/bin/perl -w
#
# This file is the handler for incoming requests.
#
# This generic wrapper will eventually be replaced by the `psa' script
#

use strict;
use lib "lib";

use T2::Schema;
use T2::Storage;
use PSA qw(Acceptor::AutoCGI Config Request::CGI Response::HTTP Cache
	   Heap);

use constant SITENAME => "psatest";

#---------------------------------------------------------------------
#  init code
#---------------------------------------------------------------------
use vars qw($storage $schema $page_cache $template_obj $acceptor
	    $config);

$config ||= PSA::Config->new;

$acceptor ||= PSA::Acceptor::AutoCGI->new;

# Load the application Schema
$schema ||= do {
    my $x = T2::Schema->read(SITENAME); $x->generator; $x;
};

# Connect to the application database
$storage      ||=
    T2::Storage->open(SITENAME, $schema->schema);

# Set up the page cache, similar to Apache::Registry
$page_cache   ||= PSA::Cache->new( base_dir => "psa-bin",
				   stat_age => 10         );

#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
#  main application loop
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
while (my $request = $acceptor->get_request()) {

    # optional - so any prints go somewhere (hopefully) visible
    select(STDERR);

    # build the PSA object; this object is valid for a single request
    my $psa = PSA->new(
		       response => PSA::Response::HTTP->new(),
		       request => $request,
		       cache => $page_cache,
		       storage => $storage,
		       schema => $schema,
		       acceptor => $acceptor,
		      );

    # In this simple example, it is assumed that every request is a
    # dynamic request and therefore requires a session.  For other
    # projects, this could be moved inside whassap.pl
    $psa->attach_heap();
    # $psa->attach_session();    # Loads session from DB instead

    #----------------------------------------
    # Wicked, now whassap.pl - result comes back in $psa->response
    $psa->run("whassap.pl");

    # Unload the heap as quickly as possible
    $psa->detach_heap();

    $psa->run("issue.pl");

    # Optional, but recommended : unload all cached objects from
    # Tangram's cache
    $storage->unload_all();

    # Let the cache know that it can start stat()'ing files again,
    # assuming they weren't stat()'ed too recently.
    $page_cache->flush_stat();

    last if $acceptor->stale();

}
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
