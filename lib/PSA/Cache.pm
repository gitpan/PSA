
package PSA::Cache;

=head1 NAME

PSA::Cache - Cache of compiled scripts

=head1 SYNOPSIS

    my $cache = new PSA::Cache
    (
     base_dir => "psa-bin/",
     default_type => {
		      '\.psa$' => "PSA",
		      '\.pl$' => "Perl",
		     },
     includes_dirs => [ "/usr/lib/psa/bin",
                        "/usr/local/lib/libfoo-psa/" ],
    )

    $cache->run("script.psa", @args);

=head1 DESCRIPTION

The PSA Cache is a useful tool for managing large programs built up of
several small scripts.

PSA `scripts' are much like calling a function, except that
preprocessing can be performed (without having to meddle with Perl
source filters), and if the file is changed on the disk, the function
will be re-loaded, without having to restart the entire server.

The PSA::Cache is inherantly designed for imperative styles of coding.
Run this, call this include, etc.  It is equivalent to modules like
L<Apache::Registry> for basic C<mod_perl> installations, or the method
of using L<Module::Reload> with imperative-style methods of objects,
such as Apache Handlers in C<mod_perl>.

Perhaps the best way to get a feel for it is to browse the sample
applications, in F<examples/> in the L<PSA> distribution.

The way it works under the hood is this:

=over

=item

The script is preprocessed to a piece of perl, that must return a CODE
reference (ie, it simply declares a subroutine).  This preprocessing
is performed by L<PSA::Cache::Entry> or a sub-class as selected by
C<default_type>.

=item

That script is placed in its own package/namespace, and then
C<eval()>'d into a compiled piece of perl.  Whilst I haven't got this
working with the Safe module yet (see L<Safe>), this is a handy place
to put such a hook, which would give the whole system that extra level
of security if you can't trust the components to be behaved.  Normally
this is locking the door after the horse has bolted, though.

=item

When you call C<$cache->run("script", @args)>, that script is looked
up, possibly C<stat> (see L<perlfunc>) is called to see if the file
has changed since we last called it, and then the code ref is called
with the arguments you pass.

=back

=cut

use strict;
use Carp;

use vars qw(@ISA @EXPORT_OK $schema);
use Exporter;
@ISA = qw(Exporter Class::Tangram);
@EXPORT_OK = qw($schema);

use PSA::Cache::Entry;
use Fcntl qw(S_IXUSR S_IXGRP S_IXOTH S_IFREG S_ISDIR);

# While it is not expected that these will be stored in a database,
# due to lack of complete stability of the B::Bytecode backend

=head1 OBJECT PROPERTIES

The B<PSA::Cache> object has several properties useful for configuring
the cache.  These can be set in any of the styles accepted by
L<Class::Tangram>, such as passing to C<-E<gt>new()>, C<-E<gt>set()>,
or by calling the auto-generated accessor/mutators
C<-E<gt>property()>, C<-E<gt>get_property()> and/or
C<-E<gt>set_property>.

Using the standard L<psa> script, these can be configured in the
C<cache:> top level config key;

 cache:
   base_dir: psa-bin/
   index: handler.pl
   includes_dirs:
      - inc/*/psa-bin
      - '/abc/local/share/psa'

=over

=item C<base_dir>

This option is always required, so must be passed when the object is
constructed.  This is the "primary" directory to find C<psa-bin>
scriptlets.

=item C<index>

Specify the name for index/fallback scriptlets.  Defaults to
F<index.pl>

=item C<cwd>

Specify the working directory for this PSA cache.  This is changed to
before all operations relating to this cache.  Defaults to the current
working directory.

=item C<default_type>

This is a hash from a regular expression applied to a file found in
the Cache (or an included location somewhere).  The target of the
cache is taken to be a package name, with C<PSA::Cache::Entry::>
prepended to it if doesn't have any C<::> delimiters in it.

These are `handlers' for different styles of scripts.  Normally, you
just want to the C<Perl> handler, implemented by
L<PSA::Cache::Entry::Perl>.  There is also a default
L<PSA::Cache::Entry::PSA> for those that like to combine the
controller + view components of an application, PHP style.  This is a
much more rapid development method, but in practice has been
discovered to be an ultimately flawed approach in the long run.

=item C<include_dirs>

Specifies a list of paths to check for after fully checking the
C<base_dir>.

This can be set to C<auto>, which means to look for F<inc/*/psa-bin>
once at startup, and also to scan C<@INC> for likely places for stock
scripts to have been delivered.

=item C<max_size>

Start cycling out LRU cache entries after it gets this big.  Sadly,
though, closures seldom actually end up freeing application space so
this is by default disabled, and not even implemented yet.  TO-DO.

=item C<stat_age>

Don't bother checking files in the cache for changes more often than
this number of seconds; defaults to a fairly leisurely 10 seconds.

Make this much higher to avoid unnecessary system calls.

=back

=cut

$schema =
    {
     table => "codecache",
     fields =>
     {
      # "page" holds the PSA::Cache::Entry objects
      hash => { page => { class => "PSA::Cache::Entry" },
		pkgs => { class => "PSA::Cache::Entry" },
	      },

      # Base directory of templates
      string => {   base_dir => { required => 1 },
		    index => { init_default => "index.pl" },
		    cwd => { init_default => sub {
				 my $cwd;
				 chomp($cwd = `pwd`);
				 $cwd; } },
		},
      flat_hash =>
      {
       default_type => {
			init_default => {
					 '\.pl$' => "Perl",
					 '\.psa$' => "PSA",
					},
		       }
      },
      flat_array =>
      {
       include_dirs => { init_default => "auto",
		       },
      },
      perl_dump => {
		    # holds cached stat() info
		    stat => { init_default => { } },
		   },

      int => {
	      # maximum number of entries in the code cache
	      max_size => undef,

	      # How long to keep stat() records hot for
	      stat_age => { init_default => 10 },

	      # The current time
	      now => undef,
	      },
     }
    };

#---------------------------------------------------------------------
#  create a new object cache
#---------------------------------------------------------------------
sub new($;@) {
    my ($class, %options) = (@_);

    my $self = $class->SUPER::new(%options);

    $self->{page} ||= { };

    bless $self, $class;
    return $self;
}

#---------------------------------------------------------------------
#  add_script($filename, $type)
# add a perl script to the cache.  FIXME: Cwd (?)
#---------------------------------------------------------------------
sub add_script($$;$) {
    my ($self, $filename, $type) = (@_);
    $self->isa(__PACKAGE__) or croak "type mismatch";

    my ($real_filename, $stat) = $self->stat_file($filename);
    $type ||= $self->type($real_filename);

    if ( $type eq "Perl" ) {
	$type = "PSA::Cache::Entry";
    } elsif ( $type !~ m/::/ ) {
	$type = "PSA::Cache::Entry::$type";
    }
    #print STDERR "Type is $type\n";

    if (not exists $self->{page}->{$real_filename}) {
	$self->expire_entries;
	$self->{page}->{$real_filename} =
	    $type->new(filename => $stat->[14]."/".$real_filename);
    }

    my $entry = $self->{page}->{$real_filename};
    $entry->load_and_compile;
    $self->{pkgs}->{$entry->pkg} = $entry;
}

#---------------------------------------------------------------------
#  $cache->lestat($filename);
# Resolves $filename as a pathname within the page cache, and returns;
# ($filename, [ stat ])
#---------------------------------------------------------------------
sub lestat {
    my $self = shift;
    my $filename = shift || croak("No filename supplied to lestat()");

    $filename =~ s{/$}{}g;

    return
	($filename,
	 $self->{stat}->{$filename} ||= do {

	     my $x;
	     # search for it in all the include paths
	     for my $path ($self->get_base_dir,
			   $self->get_include_dirs) {
		 $x = [stat _, time(), $path], last
		     if stat $path."/".$filename;
	     }
	     $x;
	 });
}

sub exists {
    my $self = shift;
    my ($filename, $stat) = $self->lestat(shift);
    return (!!$stat);
}

#---------------------------------------------------------------------
#  $cache->stat_file($filename)
# Similar to $cache->lestat(), but `follows' directories to their
# index file - returns undef if stat_file() is called with an empty
# directory as an argument
#---------------------------------------------------------------------
sub stat_file {
    my $self = shift;

    my ($filename, $stat) = $self->lestat(shift);
    return undef unless $stat;

    if ( S_ISDIR($stat->[2]) ) {
	($filename, $stat)
	    = $self->lestat($filename."/".$self->get_index);
	return undef unless $stat;
    }

    return ($filename, $stat);
}


#---------------------------------------------------------------------
#  type($filename)
# returns the type of $filename, or undef
#---------------------------------------------------------------------
sub type {
    my ($self, $filename) = (@_);

    my ($real_filename) = $self->stat_file($filename);

    if ( $real_filename && $self->{_types} ) {
	if (my @m = ($real_filename =~ m/$self->{_types}/)) {
	    my $i = 0;
	    $i++ while (not shift @m);

	    return $self->{_default_type}->[$i];
	}
    }

    return undef;
}

#---------------------------------------------------------------------
#  executable($filename)
# returns the resolved path of the given page if it is OK to run
#---------------------------------------------------------------------
sub executable {
    my $self = shift;
    UNIVERSAL::isa($self, __PACKAGE__)
	    or confess "method called as function";

    my ($filename, $stat) = $self->stat_file(shift);
    return undef unless $stat;

    # emulate -x, assume some nasty things about how file permissions
    # work :-)
    my $is_x;
    if ($stat->[4] == $>) {
	$is_x = ($stat->[2] & S_IXUSR);
    }
    if (!$is_x && $) =~ m/\b$stat->[5]\b/) {
	$is_x ||= ($stat->[2] & S_IXGRP);
    }
    if (!$is_x) {
	$is_x ||= ($stat->[2] & S_IXOTH);
    }
    return ( (($stat->[2] & S_IFREG) && $is_x) ? $filename : undef);
}

#---------------------------------------------------------------------
#  run($filename, @args)
# runs a codecache with the given arguments etc
#---------------------------------------------------------------------
sub run {
    my $self = shift or croak "PSA::Cache->run(): no object!";
    my $filename = shift or croak "PSA::Cache->run(): no filename!";

    $self->set_now(time()) unless $self->get_now();

    my ($real_filename, $stat) = $self->stat_file($filename);

    croak "`$filename' does not exist or no access" unless $stat;

    # autoload
    unless ($self->{page}->{$real_filename}) {

	if (my $type = $self->type($real_filename)) {
	    $self->add_script($real_filename, $type);
	    if ( ref $self->{page}->{$real_filename}->code ne "CODE") {
		die "page didn't compile; ".$self->errors($real_filename);
	    }
	} else {
	    croak "PSA::Cache->run(): no handler to run `$real_filename'";
	}
    }

    my $entry = $self->{page}->{$real_filename}
	or die "No Entry for file `$real_filename'";
    $entry->dirty($stat);
    $entry->set_last_used($self->get_now);

    return $entry->run(@_);
}

#---------------------------------------------------------------------
#  $cache->flush_stat()
# Clears old (>10s) stat() records from memory
#---------------------------------------------------------------------
sub flush_stat {
    my $self = shift;
    my @filenames = keys %{$self->{stat}};
    my $now = time();
    $self->set_now(undef);

    for my $fn (@filenames) {
	my $stat = $self->{stat}->{$fn};
	if (!$stat or $now - $stat->[13] >= $self->get_stat_age)
	{
	    delete $self->{stat}->{$fn};
	}
    }
}

#---------------------------------------------------------------------
#  $cache->glob("spec");
# Returns all files that match the filespec in the cache
#---------------------------------------------------------------------
sub glob {
    my $self = shift;
    my $filespec = shift;

    return map { s{^$self->{base_dir}/}{}; $_ }
	map { CORE::glob($_."/$filespec"); }
	    $self->get_base_dir, $self->get_include_dirs;
}

#---------------------------------------------------------------------
#  errors($filename)
# returns any errors associated with $filename
#---------------------------------------------------------------------
sub errors($$) {
    my ($self, $filename) = (@_);

    if (not exists $self->{page}->{$filename}) {
	return "file not in cache";
    } else {
	return ($self->{page}->{$filename}->errors);
    }
}

#---------------------------------------------------------------------
#  expire_entries
#---------------------------------------------------------------------
sub expire_entries($) {
    my ($self) = (@_);

    return 1 unless $self->{max_size};

    if (scalar keys %{$self->{page}} > $self->{max_size}) {
	#...
	croak;
    }
}


sub set_default_type {
    my $self = shift;
    my $default_type = shift;
    $self->SUPER::set_default_type($default_type);

    $self->{_default_type} = [  ];
    $self->{_types} = "";
    my $f = 0;
    while ( my ($re, $val) = each %$default_type ) {

	croak("capturing parantheses not allowed in handler regex "
	      ."(re: `$re')")
	    if ($re =~ m/\((?!\?)/);

	push @{ $self->{_default_type} }, $val;
	$self->{_types} .= ($f++ ? "|" : "") . "($re)";
    }
    $self->{_types} = qr/$self->{_types}/;
}


sub add_handler {
    my $self = shift;
    my $pattern = shift;
    my $handler = shift;

    if (!$self->{_types}) {
	$self->set_default_type({ $pattern => $handler });
    } else {
	push @{ $self->{_default_type} }, $handler;
	$self->{_types} .= "|($pattern)";
    }
    $self->{_types} = qr/$self->{_types}/;
}

sub filename {
    my $self = shift;
    my $pkg = shift;
    if (defined(my $foo = $self->{pkgs}->{$pkg})) {
	return $foo->filename;
    } else {
	return undef;
    }
}

sub harikiri {
    my $self = shift;
    $self->{enough} = 1;
}

sub ok {
    my $self = shift;
    return !$self->{enough};
}

sub set_include_dirs {
    my $self = shift;
    my $value = shift;
    if ( ref $value ) {
	$self->SUPER::set_include_dirs(@_);
    } else {
	opendir INC, "inc/" or return;
	my @include_dirs;
	my @entries = grep !/^\.\.?$/, readdir INC;
	closedir INC;

	for my $ent ( @entries ) {
	    my $path = "inc/$ent";
	    next unless -d $path;
	    if ( -d "$path/psa-bin" ) {
		push @include_dirs, "$path/psa-bin";
	    }
	}

	$self->SUPER::set_include_dirs(\@include_dirs);
    }
}

"hempseed is the only perfect source of protein for humans from a plant";

__END__

=head1 SEE ALSO

L<PSA>, L<PSA::Cache::Entry>, L<PSA::Cache::Entry::Perl>,
L<PSA::Cache::Entry::PSA>

=cut
