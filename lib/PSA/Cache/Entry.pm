package PSA::Cache::Entry;

=head1 NAME

PSA::Cache::Entry - an entry in a PSA::Cache

=head1 SYNOPSIS

 my $entry = PSA::Cache::Entry->new

=head1 DESCRIPTION

t.b.c.

=cut

use strict;
BEGIN { eval "use warnings;" };
use Carp;
use IO::File;

use Exporter;
use Class::Tangram;
use vars qw($schema @ISA);
@ISA = qw(Exporter Class::Tangram);

=head1 ATTRIBUTES

=cut

# it is not expected that these will be stored in a database, due to
# a lack of stability of the B::Bytecode backend.
$schema =
    {
     table => "compiled_pages",
     fields =>
     {
      # FIXME - perl_dump doesn't work with CODE refs
      perl_dump => [ qw(code source preprocessed) ],
      string => [ qw(filename cwd error pkg) ],
      int => [ qw(last_used last_stat dirty mtime owner size) ],
     }
    };

our $DEBUG = 0;

sub _say {
    print STDERR __PACKAGE__.": @_\n";
}

=over

=item filename

The filename of the entry (string)

=item cwd

The working directory to change to when running this sub

=item error

Contains the error string from compilation/run/etc

=item size

=item mtime

=item owner

Vital statistics to check for a new version of the source file

=item code

A closure to call to run this entry

=item last_used

The time() when this function was last called.

=back

=head1 METHODS

=head2 preprocess

=cut

our $num = 0;

our $DEBUG_PAGES = 0;

sub preprocess {
    my $self = shift;

    my (undef, $filename, $line_no) = (sub { caller() }->());
    $line_no += 21;       # num. lines from this and usage, +2
    # FIXME - use a safe
    #print STDERR __PACKAGE__." - I am $filename : $line_no\n";

    chomp(my $full_filename = `pwd`);
    $full_filename .= "/".$self->{filename};
    $full_filename =~ s{//+}{/}g;

    if ($DEBUG_PAGES) {
	no strict 'refs';
	my @code = split /(?=\n)/, $self->{source};
	@{"main::_<".$full_filename}[1..@code]
	    = @code;
	${"main::_<".$full_filename} = $full_filename;
    }

    $self->{preprocessed} = "
package PSA::Root::Perl$num;

# line $line_no \"$filename\"
our \$__GO__ = sub {
Perl$num".": {
# line 1 \"$full_filename\"
$self->{source};
# line ${\( $line_no + 4 )} \"$filename\"
}
};
";
    #kill 2, $$;
    my $pkg_filename;
    $self->set_pkg($pkg_filename = "PSA::Root::Perl$num");
    $pkg_filename =~ s{::}{/}g;
    $pkg_filename .= ".pm";
    $INC{$pkg_filename} = $full_filename;
    $num++;

    # don't need this any more
    delete $self->{source};
    return 1;
 }

=head2 compile(\$script)

Force a compilation of the source file (the contents of which are
passed as the argument), returns true or croaks with compilation
error/warning/file not found/etc.

Note that for the compile, the B<cwd> attribute is not used.  That is
because it is not usually what you want, I think.

=cut

sub compile($$) {
    my $self = shift;
    my $script = shift;
    $self->isa("PSA::Cache::Entry") or confess "type mismatch";

    # compile it.  Do we care about the CWD for compiles?
    delete $self->{error};
    delete $self->{code};
    local $SIG{'__WARN__'} = sub { $self->{error} .= $_[0]; };
    local $SIG{'__DIE__'} = sub { $self->{error} .= $_[0]; };

    # note the use of the compiler directive to tell it where the
    # source file is!  Also
    $self->{code} = DMZ::eeval($self->{preprocessed});
    $self->{error} .= $@ if ($@);
    #die $@ if $@;
    if (ref $self->{code} ne "CODE" or $self->{error}) {
	delete $self->{code};
	return undef;
    }
    return $self->{code};
}

=head2 load

Read a file in from disk.  You probably don't want to overload this
method; overload preprocess instead.

=cut

sub load {
    my $self = shift;
    $self->isa("PSA::Cache::Entry")
       or confess "type mismatch";

    # read the file in
    delete $self->{error};
    local ($/) = undef;
    my $fh = new IO::File;
    $fh->open("< $self->{filename}")
        or do { $self->{error} = "Cannot open file; $!";
                return undef;                            };
    $self->{source} = <$fh>;
    my @stat = stat $fh;
    $fh->close;

    $self->{size} = $stat[7];
    $self->{mtime} = $stat[9];
    $self->{owner} = $stat[4];

    return 1;
}

=head2 load_and_compile

Read a perl script in and compile it

=cut

sub load_and_compile($) {
    my ($self) = (@_);
    $self->isa("PSA::Cache::Entry") or croak "type mismatch";

    $self->load() or return undef;
    $self->preprocess() or die $self->{error};
    $self->compile();
}

=head2 update

Makes an entry current; that is, reloads it if has changed

=cut

sub update($) {
    my ($self) = (@_);
    $self->isa("PSA::Cache::Entry") or croak "type mismatch";

    $self->load_and_compile if ($self->dirty);
}

=head2 dirty($stat)

Given some stat information, will mark self as dirty if it's newer
than ourself

=cut

sub dirty {
    my $self = shift;
    my $stat = shift;

    if ($stat) {
	if (!$self->{code} 
	    or $self->{size} != $stat->[7]
	    or $self->{mtime} != $stat->[9]
	    or $self->{owner} != $stat->[4] ) {

	    $self->set_dirty(1);
	}
    }
    return $self->get_dirty();
}

=head2 run( @argument_list)

Runs a cache entry and returns its return

=cut

sub run($;@) {
    my $self = shift;

    $self->update;

    _say "thread ".$_[0]->threadnum." running $self->{filename}".((@_>1)?"(".join(", ", map { defined($_)?"\"$_\"" : "undef" } @_[1..$#_]).")":"")
	if $DEBUG;

    if ( $self->{code} ) {
	goto $self->{code};
    } else {
	die $self->{error};
    }

}

=head2 errors

An alias for the get_error() method.

=cut

sub errors($) {
    my ($self) = (@_);
    return $self->{error};
}

=head1 SEE ALSO

L<PSA::Cache>, L<PSA::Cache::Entry::ePerl>

=cut

{ package DMZ; sub eeval { return (eval $_[0]); } }

"legalise Cannabis!";
