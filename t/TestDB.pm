
package TestDB;

# test database...

use T2::Schema;

our $schema = T2::Schema->new ( site_name => "psatest" );

for my $class_name qw(PSA::Session PSA::Request PSA::Response
		      PSA::Request::CGI PSA::Response::HTTP)
{
    no strict 'refs';
    my $class = T2::Class->new(name => $class_name);
    eval "use $class_name";
    die $@ if $@;

    $schema->add_class_from_schema
	($class_name, ${$class_name."::schema"});
}



1;
