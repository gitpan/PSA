#   -*- perl -*-

package POE::Session::PSA;

=head1 NAME

POE::Session::PSA - POE Sessions from PSA Caches

=head1 SYNOPSIS

  # `from basics' - the
  my $session = POE::Session::PSA->create
      (cache => PSA::Cache->new(...),
       root  => "/something",    # `root' dir of session
       ...                       # normal POE::Session args
      );

  # normal usage in a PSA page
  my $thread = $psa->cache->mk_session
      (root => "/something",
       ...
      );

=head1 DESCRIPTION

A POE::Session::PSA is very much like a regular POE session, except
that its states are automatically pulled from the PSA code Cache (see
L<PSA::Cache>).

What this means is that `states' of the POE Session are essentially
PSA::Cache pages.

To best use this, pages are required to use C<$psa-E<gt>yield("page")>
rather than C<$psa-E<gt>run("page")> to invoke the `next' action that
they want to do.  C<$psa-E<gt>run("page")> still works, but you lose
many of the advantages of POE.

It is not required to list all the states

=cut

use POE;
use base qw(POE::Session);
use PSA qw(POE Cache);
use strict;
use Carp qw(confess);

=head1 INTERFACE

=head2 B<POE::Session::PSA-E<gt>create(...)>

Creates a new PSA POE session, and returns it.

=cut

our $fallback_cache;

sub DEBUG     () { 0 }
sub debug { print STDERR __PACKAGE__.": @_\n" }

sub create {
    my $class = shift;
    (my %args, @_) = (@_);

    my ($psa, $cache, $root, $entry_point);
    $cache = delete $args{cache} || $psa->cache ||
	($fallback_cache ||= PSA::Cache->new(base_dir => "psa-bin"));
    $psa = delete $args{psa} || (new PSA::POE(cache => $cache));
    $root  = delete $args{root} || "";
    $entry_point  = delete $args{entry_point} || "whassap";

    ${ $args{inline_states}||={} }{ _start } = sub {
	$_[KERNEL]->yield($entry_point, @_[ARG0..$#_]);
    };

    my $self = $class->SUPER::create(%args);

    $root =~ s{([^/])$}{$1/};

    {
	no warnings;
	DEBUG && debug "new - psa=$psa, cache=$cache, root=$root, "
	    ."entry=$entry_point";
    }

    tie %{ $self->[POE::Session::SE_STATES] },
	"POE::Session::PSA::Cache",
	$psa, $cache, $root, $entry_point;

    $self;
}

package POE::Session::PSA;

sub PSA_PSA   () { 0 }
sub PSA_CACHE () { 1 }
sub PSA_ROOT  () { 2 }
sub PSA_ENTRY () { 3 }

sub POE::Session::PSA::Cache::TIEHASH { bless \@_, (shift) } # :)

sub POE::Session::PSA::Cache::FETCH {
    my $self = shift;
    my $key  = shift;
    my $path = $self->[PSA_ROOT].$key.".pl";
    #DEBUG && debug "fetch - key=$key";
    if ($key eq "_start" and not $self->[PSA_CACHE]->exists($key)) {
	DEBUG && debug "_start - returning builtin";
	return sub {
	    $_[KERNEL]->post($_[SESSION], $self->[PSA_ENTRY], @_[ARG0..$#_]);
	}
    } elsif ($key eq "_child") {
	return sub {
	    if ($self->[PSA_CACHE]->exists($path)) {
		DEBUG && debug "_child - yielding _child";
		$_[SESSION]->yield($self->[PSA_ENTRY], @_[ARG0..$#_]);
	    }
	    if ($_[ARG0] eq "lose") {
		DEBUG && debug "_child - calling ->_child()";
		my $child = $_[ARG1];
		$self->[PSA_PSA]->_child($child);
	    }
	};
    }
    (DEBUG>1) && debug "fetch - returning new closure for $key";
    return sub {
	DEBUG && debug "$key - running (offset $self->[PSA_ROOT])";
	$self->[PSA_CACHE]->run
	    ($path,
	     $self->[PSA_PSA],
	     @_[ARG0..$#_]);
    }
}

use Carp qw(confess);

sub POE::Session::PSA::Cache::STORE {
    confess "No STORE allowed!  :-)";
}

sub POE::Session::PSA::Cache::DELETE {
    confess "No DELETE allowed!  :-)";
}

sub POE::Session::PSA::Cache::CLEAR {
    confess "No CLEAR allowed!  :-)";
}

sub POE::Session::PSA::Cache::EXISTS {
    my $self = shift;
    my $key  = shift;
    my $exists =
	$self->[PSA_CACHE]->exists($self->[PSA_ROOT].$key.".pl");

    if (not $exists and $key eq "_start" and $self->[PSA_ENTRY]) {
	$exists = 1;
    } elsif (not $exists and $key eq "_child") {
	$exists = 1;
    }
    (DEBUG>1) && debug "exists - returning `$exists' for key `$key'";

    $exists;
}

sub POE::Session::PSA::Cache::FIRSTKEY {
    # shoite!
    confess "No FIRSTKEY allowed!  :-)";
}

sub POE::Session::PSA::Cache::NEXTKEY {
    # shoite!
    confess "No NEXTKEY allowed!  :-)";
}

1;

__END__
