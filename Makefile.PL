use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

eval "use T2::DBSetup";
warn($@), goto NOTESTS if $@;

use lib "lib";
use lib "t";
eval "use TestDB";
warn($@), goto NOTESTS if $@;

print "LOADED TestDB\n";
my $schema = $TestDB::schema;

T2::DBSetup->deploy("psatest", $schema)
    or goto NOTESTS;

system("cp", "t/psatest.dsn", "t/psatest.t2", "examples/etc");

print("Use `make test' to run the test suite.\n");

NOTESTS:

WriteMakefile
    (
     'NAME'		=> "PSA",
     'PREREQ_PM'        => {
			    Set::Object => 1.04,
			    Class::Tangram => 1.50,
			    URI => 1.18,
			    File::MMagic => 1.15,
			    Maptastic => 0,
			    T2 => 0.08,
			   },
     'VERSION_FROM'     => "lib/PSA.pm",
     ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT         => "Perl Server Applications - appdev framework",
       AUTHOR           => "Sam Vilain <samv@cpan.org>") : ()),
     clean => { FILES => "t/psatest.t2 examples/etc/psatest.*" },
    );


