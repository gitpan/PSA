
my $psa = shift;

Test::More::pass($psa->heap->{name}.": got to forkit");

my $name = $psa->heap->{name};

$name =~ s{manager}{thread 1};

my $child = $psa->spawn(entry_point => "t2/doit.pl");

$child->heap->{name} = $name."";

$name =~ s{1}{2};

$child = $psa->spawn(entry_point => "t2/doitagain.pl");
$child->heap->{name} = $name;

$psa->wait($child, "yoyo", "yo");
