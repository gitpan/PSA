package Profiling;

use Time::HiRes qw(gettimeofday tv_interval);
use POSIX qw(ceil);
use base qw(Exporter);
our @EXPORT_OK = qw(time_this sci_unit);

sub time_this(&) {
    my $block = shift;

    my $t1 = [ gettimeofday ];
    my $t2 = [ gettimeofday ];
    &$block();
    @$t2 = gettimeofday;
    return sci_unit(tv_interval($t1, $t2), 4, "s");
}

my %prefixes = ( 18 => "E", 15 => "P", 12 => "T",
		 9 => "G",  6 => "M",  3 => "k",
		 0 => "",  -3 => "m", -6 => "µ",
		 -9 => "n",-12 => "p",-15 => "f",
		 -18 => "a"
	       );

sub sci_unit {

    my $scalar = shift;
    my $d = (shift) || 4;
    my $unit = (shift) || "";

    my $e = 0;

    while ( abs($scalar) > 1000 ) {
	$scalar /= 1000;
	$e += 3;
    }

    while ( $scalar and abs($scalar) < 1 ) {
	$scalar *= 1000;
	$e -= 3;
    }

    # round the number to the right number of digits with sprintf
    if (exists $prefixes{$e}) {
	$d -= ceil(log($scalar)/log(10));
	my $a = sprintf("%.${d}f", $scalar);
	return $a.$prefixes{$e}.$unit;
    } else {
	return sprintf("%${d}e", $scalar).$unit;
    }

}

