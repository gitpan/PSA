
my $psa = shift;
my $args = shift;

my $seen_num;

our @words;

BEGIN {
@words = (map { ucfirst }
	  grep /^\w{1,7}$/,
	  split /\n/,
	  `cat /usr/share/dict/words`);

@words or (@words = qw(Cheese Bananas Oranges Apples Terence Delicious
		       Willis Carrot Phone Scissors Stapler Character
		       Dragon Horse Snake Dog Cat Sheep Rabbit Rat));
}
my @parts;

my $pass = "";
my $L = 6;

while ( length($pass) < $L ) {
    if ( !$seen_num and (rand(3) > 2) ) {
	my $num = int(rand(50));
	push @parts, { type => "number", value => $num };
	$pass .= $num;
	$seen_num = 1;
    } else {
	my $word = $words[rand($#words)];
	my $length = int(rand(3)) + 2;
	$length = length($word) if $length > length($word);

	my ($value, $type);
	if ( $length == length($word) ) {
	    $type = "word";
	    $value = $word;
	}
	elsif ( rand(2) > 1 ) {
	    $value = substr($word, 0, $length);
	    $type = "startword";
	    # look for shorter words...
	    for my $w ( @words ) {
		(length($w) < length($word)) &&
		    ($w =~ m/^$value/) && do {
			print STDERR "genpasswd: Changed $word to $w\n";
			$word = $w;
		    };
	    }
	} else {
	    $value = substr($word, length($word) - $length);
	    $type = "endword";
	    # look for shorter words...
	    for my $w ( @words ) {
		(length($w) < length($word)) &&
		    ($w =~ m/$value$/) && do {
			print STDERR "genpasswd: Changed $word to $w\n";
			$word = $w;
		    };
	    }
	}
	$type = "word" if $length == length($word);

	$pass .= $value;
	push @parts, { type => $type,
		       value => $value,
		       word => $word,
		       num => $length,
		     };
	if ( length($pass) >= $L and !$seen_num ) {
	    print STDERR "genpasswd: no number; getting drastic\n";
	    my $num = int(rand(50));
	    push @parts, { type => "number", value => $num };

	    do {
		@parts = sort { (rand(2) - 1) <=> 0 } @parts;
		$pass = join "", map { $_->{value} } @parts;
		print STDERR "genpasswd: pass now $pass (shuffle)\n";
	    } while ( $pass =~ m/^\D{$L}/ );

	    while ( (length($pass) - length($parts[$#parts]->{value}))
		    >= $L
		  ) {
		pop @parts;
		$pass = join "", map { $_->{value} } @parts;
		print STDERR "genpasswd: pass now $pass (pop)\n";
	    }
	}
    }
}
$args ||= { };

$psa->response->set_template
    ([ Template => "prefs/passwd.html",
       {
	p => \@parts,
	pass => $pass,
	%$args,
       } ]);
