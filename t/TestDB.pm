
package TestDB;

# test database...

use T2::Schema;

our $schema = T2::Schema->new ( site_name => "psatest" );

for my $class_name qw(PSA::Session PSA::Request PSA::Response
		      PSA::Request::CGI PSA::Response::HTTP)
{
    print STDERR "loading $class_name\n";
    no strict 'refs';
    print STDERR "loading $class_name - a\n";
    my $class = T2::Class->new(name => $class_name);
    print STDERR "loading $class_name - b\n";
    eval "use $class_name";
    print STDERR "loading $class_name - c\n";
    die $@ if $@;

    if ( 0 ) {
    $class->set_from_fields(${$class_name."::schema"}->{fields}
			    ||${$class_name."::fields"}
			    ||die"no fields for class `$class_name'");

    $schema->classes_insert($class);

    $class->set_superclass($schema->class($_))
	foreach @{${$class_name."::schema"||{}}->{bases}||[]}
    } else {
    print STDERR "loading $class_name - d\n";
	$schema->add_class_from_schema
	    ($class_name, ${$class_name."::schema"});
    print STDERR "loading $class_name - e\n";
    }
}



1;
