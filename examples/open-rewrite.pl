#!/usr/bin/perl -w

use strict;

# An example of a URL rewriter that allows "webroot includes" and
# optionally permits directory indexing (note: only on the primary
# webroot, not included directories).  For this to work, it must be
# configured in the Apache config like this:

#    RewriteEngine On
#    RewriteLog /var/log/apache/rewrite.log
#    RewriteLogLevel 1
#
#    # Use an external program for URL rewriting
#    RewriteMap nexus prg:/var/www/yourapp/rewrite.pl
#    RewriteCond %{SCRIPT_FILENAME} !(/$|/index.(s?html?|cgi)$|^/404.cgi)
#    ReWriteRule (.*) ${nexus:$1}

# This hack is only necessary for Apache.  Most other web servers
# handle internal redirects correctly.

use constant WEBROOT => "/var/www";
use constant INCLUDE_PATHS =>
    qw( .
	/usr/lib/psa
	/usr/share/apache
      );
use constant OK_EXTENSIONS =>
    qw( html?
	jpe?g
	gif
	png
	js
	css
	swf
      );

# everything that is not a flat file found in the above include paths
# goes here
use constant DEFAULT_SCRIPT => "index.cgi";
use constant ALLOW_INDEXING => 1;
use constant LET_THROUGH => qr{/index.(s?html?|cgi)$
			       |^/\Q${\(DEFAULT_SCRIPT)}\E}x;

# how many seconds to keep positive cache entries `hot'
use constant CACHE_TTL => 30;

$| = 1;

# Apache, you suck.  The rewriting program is not started with the
# webroot as its current working directory, so it must change there
# itself.
chdir(WEBROOT);

( -d "inc" ) || (mkdir "inc", 0755) or die "Failed to make `inc'; $!";

# setup symlinks to the include paths that are within the webroot
my @short_inc;
for (INCLUDE_PATHS) {
    if ( m{^/.*/(.*)} ) {
	if ( -l "inc/$1" ) {
	    if (readlink("inc/$1") ne $_) {
	        unlink "inc/$1" or die "failed to remove inc/$1; $!";
	    }
	}
	if ( ! -l "inc/$1" ) {
	    symlink($_, "inc/$1") or die "failed to make inc/$1; $!";
	}
	push @short_inc, "./inc/$1";
    } else {
	push @short_inc, $_;
    }
}

# Note that too much printing to STDERR makes the program block and
# hangs Apache :-)

#print STDERR "Including files from @{[INCLUDE_PATHS]} (@short_inc)\n";
my $flat;
my $ok_ext = join("|", map { "\Q$_\E" } OK_EXTENSIONS);
my %dcache = ();
my $last_checked = time();
while (<>) {

    chomp;
    $flat = 0;

    if (m{^/X/}) {

	# to avoid potential loops, if the back-end signals a flat
	# file with Location: /X/..., just remove the prefix
	s{/X/}{/};
	$flat = 1;

    } elsif (ALLOW_INDEXING && m{${\(LET_THROUGH)}}o) {

	$flat = 1;

    } else {

	# just do a simple sweep of the cache every Xs
	if ((my $t=time()) - $last_checked > CACHE_TTL) {
	    %dcache = ();
	    $last_checked = $t;
	}

	# flat files are shortcut to the real thing
	if (m{^/([\w\-]+/)*[\w\-]+(\.($ok_ext))?$|^/$}o) {

	    # allow files to be present in alternate paths
	    if (my $x = $dcache{$_}) {
		$_ = $dcache{$_};
		$flat = 1;
	    } else {
		for my $path (@short_inc) {
		    if ( -r "$path$_" ) {
			my $old = $_;
			s{^}{$path};
			s{^/*\.?/}{/}g;
			$flat = 1;
			$dcache{$old} = $_;
			last;
		    } else {
			#print STDERR "$0: not found in $path$_\n";
		    }
		}
	    }
	    #print STDERR "$0: path now $_\n";
	} else {
	    #print STDERR "$0: bad filename for rewrite\n";
	}
    }

    # everything not found goes to the index or 404 script
    s{^}{"/".DEFAULT_SCRIPT}e unless $flat;

    print "$_\n";
}
