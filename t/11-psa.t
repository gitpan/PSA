#!/usr/bin/perl -w

use Test::More tests => 4;
use Scriptalicious;
    #-progname => '';

=head1 NAME

11-psa.t - tests end-to-end PSA

=head1 SYNOPSIS

 perl -Mlib=lib t/11-psa.t

=head1 DESCRIPTION

This script tests that the example PSA webroot can serve requests.

=head1 COMMAND LINE OPTIONS

=over

=item B<-h, --help>

Display a program usage screen and exit.

=item B<-V, --version>

Display program version and exit.

=item B<-v, --verbose>

Verbose command execution, displaying things like the
commands run, their output, etc.

=item B<-q, --quiet>

Suppress all normal program output; only display errors and
warnings.

=item B<-d, --debug>

Display output to help someone debug this script, not the
process going on.

=back

=cut

use strict;
use warnings;

our $VERSION = '1.00';

my $next;

$ENV{SUCK_DUMMY} = 1;
$ENV{PERL5LIB}   = join(":", map { m{^/}?$_:"../$_" } @INC);

{
    my ($rc, @output)
	= capture_err("/bin/sh", "-c",
		      "cd examples && $^X index.cgi 2>&1");

    is($rc, 0, "index.cgi returned true" );
    my $out = join "", @output;
    like($out, qr/302 Found/, "first hit is a redirect");

    ($next) = ($out =~ m{Location: (\S*)});
}

{
    my ($path_info) = ($next =~ m{index.cgi(/\S*)});
    $ENV{PATH_INFO} = $path_info;

    my ($rc, @output)
	= capture_err("/bin/sh", "-c",
		      "cd examples && $^X index.cgi 2>&1");

    is($rc, 0, "index.cgi returned true" );
    my $out = join "", @output;
    like($out, qr/Hello, world!/, "second hit is a page");

}
