#!/usr/bin/perl -w
#
# here's a slightly more modern version of the examples/psa.cgi script.
#
# this sort of thing will be handled by bin/psa, PSA::Init and friends
# later.

use Scriptalicious
    -name => "psa_handler";

use strict;
use warnings;

use PSA qw(Acceptor::AutoCGI
	   Cache
	   Config
	   Request::CGI Response::HTTP
	   Session);

use BNZMV;

use Maptastic;

our $VERSION = '1.00';

use lib "lib";

#---------------------------------------------------------------------
#  init code
#---------------------------------------------------------------------
use vars qw($storage $schema $page_cache $template_obj $acceptor
	    $config);

$config ||= PSA::Config->new;

$0 = "BNZ.MV - $config->{uri_top}";

if ( my $env = $config->{env} ) {
    while ( my ($key, $value) = each %$env ) {
	if (exists($ENV{$key})) {
	    moan "overriding config: $key=$ENV{$key}";
	} else {
	    $ENV{$key} = $value;
	}
}

if ( my $globals = $config->{globals} ) {
    no strict 'refs';
    map_each { ${$_[0]} = $_[1] } $globals;
}

$acceptor ||= PSA::Acceptor::AutoCGI->new(base => $config->{uri_top});

# Load the application Schema
$schema ||= BNZMV->schema;

# Connect to the application database
$storage ||= BNZMV->storage;
$acceptor->add_pre_fork(sub { $storage->disconnect() });
$acceptor->add_post_fork(sub { $storage = BNZMV->storage });

# Set up the page cache, similar to Apache::Registry
$page_cache   ||= PSA::Cache->new( base_dir => "psa-bin",
				   stat_age => 10         );

#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
#  main application loop
#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
while (my $request = $acceptor->get_request()) {

    $page_cache->flush_stat();

    # optional - so any prints go somewhere (hopefully) visible
    select(STDERR);

    # build the PSA object; this object is valid for a single request
    my $psa = PSA->new(
		       config => $config,
		       response => PSA::Response::HTTP->new(),
		       request => $request,
		       cache => $page_cache,
		       storage => $storage,
		       schema => $schema,
		       acceptor => $acceptor,
		      );
    $psa->{times} = [];
    start_timer();

    reload();

    push @{ $psa->{times} }, "reload: ".show_delta;

    # Wicked, now whassap.pl - result comes back in $psa->response
    $psa->run("whassap.pl");
    push @{ $psa->{times} }, "page: ".show_delta;

    $psa->run("issue.pl");
    push @{ $psa->{times} }, "issue: ".show_delta;

    last if $acceptor->stale();

    say("times[$$]: ".join(", ", @{$psa->{times}}, "total: ".show_elapsed())
	." - ".$psa->request->filename)
	unless $psa->request->filename =~ m{\.(js|css)$};

    $storage->recycle("clear_refs");

    $Tangram::TRACE = undef unless $ENV{TANGRAM_TRACE};
}

#-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

my $Debug = 1;
my %Stat;
sub reload {
    my $c=0;
    while (my($key,$file) = each %INC) {
	next unless $file =~ m{Fozzie};
	local $^W = 0;
	my $mtime = (stat $file)[9];
	$Stat{$file} = $^T
	    unless defined $Stat{$file};
	if ($mtime > $Stat{$file}) {
	    delete $INC{$key};
	    eval { 
		local $SIG{__WARN__} = \&warn;
		require $key;
	    };
	    if ($@) {
		warn "Module::Reload: error during reload of '$key': $@\n"
	    }
	    elsif ($Debug) {
		warn "Module::Reload: process $$ reloaded '$key'\n"
		    if $Debug == 1;
		warn("Module::Reload: process $$ reloaded '$key' (\@INC=".
		     join(', ',@INC).")\n")
		    if $Debug >= 2;
	    }
	    ++$c;
	}
	$Stat{$file} = $mtime;
    }
    $c;
}
