
package PSA::Heap;
use strict;

=head1 NAME

PSA::Heap - a per-session dump for data

=head1 SYNOPSIS

 my $heap = PSA::Heap->new($psa);

 $psa->heap->{foo} = "bar";

 $heap->flush();    # automatically called on destruction

=head1 DESCRIPTION

The PSA::Heap module encapsulates a `Heap' concept - analagous to a
session.  This is distinct from the PSA::Session class, in that that
class is actually a real object in a Tangram store - the PSA::Heap
class assumes that you are storing the sessions locally on the
application servers (and hence, that session affinity is working
correctly).

Apache::Session::File is used for the serialisation.

There are drawbacks to this approach, as compared to PSA::Session:

=over

=item *

Application code needs to know whether it's better to store stuff in
the heap or in the PSA::Session.

=item *

Business objects mistakenly placed in the heap may end up trying to
serialise the entire database.

=back

However, both of these problems can be worked around; by serialising
the session with Data::Dumper, but replacing any business objects (ie,
those found with a storage ID) with a blessed scalar ref to the object
ID or something like that.  This serialisation can be stored as part
of the PSA::Session if using DB-only sessions.

=cut

use Apache::Session::File;
use Storable qw(freeze thaw);
use Set::Object qw(blessed reftype);
use Data::Lazy 0.06;

use base qw(Class::Tangram);

our $fields =
    {
     int => [ qw(fresh last_used sent_cookie) ],
     perl_dump => [ qw(session_h psa) ],
    };

=head2 Session State and lock directories

The following directories are checked for writability in order at
program startup:

  var/lib/session
  /var/lib/psa
  /var/tmp

The first one that is found, and writable, is used to store session
information.

For session locking information, the following paths are used:

  var/lock
  /var/lock/psa
  /tmp

=cut

use vars qw($CONFIG);
use constant DEBUG => 0;

BEGIN {

    $CONFIG = { Transaction => 1 };

    for my $dir (qw(var/lib/session /var/lib/psa /var/tmp)) {
	( -d $dir && -w _ ) && do {
	    $CONFIG->{Directory} = $dir;
	    last;
	}
    }

    for my $dir (qw(var/lock /var/lock/psa /tmp)) {
	( -d $dir && -w _ ) && do {
	    $CONFIG->{LockDirectory} = $dir;
	    last;
	}
    }

}

=head1 METHODS

=over

=item PSA::Heap->new($psa)

Creates or loads a new session.  The PSA object will supply the SID to
use if a session is to be resumed; otherwise (or if the session cannot
be resumed), a new session is created and the SID set in the PSA
object.

=cut

sub new {
    my $class = shift;
    my $psa = shift;
    my $storage = shift;

    my $self = $class->SUPER::new(@_);

    my %session;
    $self->set_session_h(\%session);
    eval {
	die "no sid" unless $psa->sid;
	DEBUG &&
	    print STDERR "PSA::Heap[$$]: attach ".$self->sid."\n";
	tie %session, 'Apache::Session::File', $psa->sid, $CONFIG
	    or die $!;
    };
    if ($@) {
	tie %session, 'Apache::Session::File', undef, $CONFIG
	    or die $!;
	DEBUG &&
	print STDERR "PSA::Heap[$$]: new $session{_session_id}\n";
    }
    my $now = time();

    $session{heap} ||= { created => $now, do{$self->set_fresh(1);()},
			 ($psa->request ?
			  (referer => $psa->request->referer) : ()),
		       };
    $self->set_last_used($session{last_used});
    $session{last_used} = $now;
    ($session{hits} ||= 0)++;

    $psa->set(  sid => $session{_session_id},
	       heap => $session{heap},
           heap_obj => $self,
	     );

    $self->set_psa($psa);
    $self->unflatten($storage) if $storage;

    return $self;
}

=item B<$heap-E<gt>flush()>

Flushes a session; ie, explicitly commits the session to disk.  This
is automatically called on destruction of the object (but note that a
circular reference prevents this from happening normally; c'est la
vie).

=cut

sub flush {
    my $self = shift;
    $self->psa->set_heap(undef);
    DEBUG &&
	print STDERR "PSA::Heap[$$]: flush ".$self->sid."\n";
    untie(%{$self->get_session_h});
}

=item B<$heap-E<gt>flatten($storage)>

Removes any references in the heap to objects in the provided storage.
Note that after this happens, the data won't be very useful, so it
should happen after the page is generated (d'oh!).

FIXME - doesn't work for Set::Object containers

=cut

sub flatten {
    my $self = shift;
    my $storage = shift || $self->psa->storage
	or return undef;

    DEBUG > 1 && print STDERR "PSA::Heap[$$]: flattening Heap\n";

    # check for Tangram objects in the heap, replace them with
    # Mementos
    my @obj_stack;
    push @obj_stack, $self->get_session_h->{heap};
    my $seen = Set::Object->new(@obj_stack);
    while (my $obj = shift @obj_stack) {

	if (reftype $obj eq "HASH") {

	    while (my ($key, $value) = each %$obj) {

		#my $x = tied $obj->{$key};
		#if ($x and $x =~ m/^Defer/) {
		#}
		if (ref $value) {
		    if (blessed $value and
			my $id = $storage->id($value)) {

			$obj->{$key} =
			    bless \$id, "PSA::Heap::Memento";

		    } elsif ($seen->insert($value)) {
			push @obj_stack, $value
		    }
		}
	    }
	} elsif (reftype $obj eq "ARRAY") {

	    for my $i (0..$#$obj) {

		my $value = $obj->[$i];

		if (ref $value) {
		    if (blessed $value and
			my $id = $storage->id($value)) {

			$obj->[$i] =
			    bless \$id, "PSA::Heap::Memento";

		    } elsif ($seen->insert($value)) {
			push @obj_stack, $value;
		    }
		}

	    }
	} elsif (reftype $obj eq "CODE") {

	    die "Tried to store CODE reference in the Heap";

	} else {
	    if (ref $$obj) {
		if (blessed $$obj and
		    my $id = $storage->id($$obj)) {

		    $$obj = bless \$id, "PSA::Heap::Memento";

		} elsif ($seen->insert($$obj)) {
		    push @obj_stack, $$obj;
		}
	    }
	}
    }
    use Data::Dumper;
    DEBUG > 1 &&
	print STDERR "PSA::Heap[$$]: heap flattened to: "
	    .Class::Tangram::quickdump($self->get_session_h->{heap});
}

=item B<$heap-E<gt>unflatten($storage)>

Goes through the heap and un-does the effects of a flatten.  Objects
are not loaded immediately; Defer is used to avoid that.

=cut

sub unflatten {
    my $self = shift;
    my $storage = shift || $self->psa->storage
	or return undef;

    (DEBUG) &&
	print STDERR "PSA::Heap[$$]: un-flattening Heap\n";

    my @obj_stack;
    push @obj_stack, $self->get_session_h->{heap};
    use Data::Dumper;
    (DEBUG > 1) && print STDERR "Heap is: ".Dumper(@obj_stack);
    my $seen = Set::Object->new(@obj_stack);
    while (my $obj = shift @obj_stack) {

	if (reftype $obj eq "HASH") {

	    while (my ($key, $value) = each %$obj) {

		if (ref $value) {
		    if (blessed $value and
			$value->isa("PSA::Heap::Memento")) {

			my $id = $$value;
			$obj->{$key} = undef;
			(DEBUG > 1) && print STDERR "Heap: setting up Data::Lazy($id)\n";
			tie($obj->{$key}, 'Data::Lazy',
			    sub {
				(DEBUG) && print STDERR "Heap: loading object $id\n";
				$storage->load($id);
			    },
			    \$obj->{$key});

		    } elsif ($seen->insert($value)) {
			push @obj_stack, $value
		    }
		}
	    }
	} elsif (reftype $obj eq "ARRAY") {

	    for my $i (0..$#$obj) {
		my $value = $obj->[$i];

		if (ref $value) {
		    if (blessed $value and
			$value->isa("PSA::Heap::Memento")) {

			my $id = $$value;
			$obj->[$i] = undef;
			(DEBUG > 1) && print STDERR "Heap: setting up Data::Lazy($id)\n";
			tie($obj->[$i], 'Data::Lazy',
			    sub {
				(DEBUG) && print STDERR "Heap: loading object $id\n";
				$storage->load($id);
			    },
			    \( $obj->[$i] ) ),

		    } elsif ($seen->insert($value)) {
			push @obj_stack, $value;
		    }
		}

	    }
	} elsif (reftype $obj eq "CODE") {

	    die "Tried to store CODE reference in the Heap";

	} else {
	    if (ref $$obj) {
		if (blessed $$obj and
		    $$obj->isa("PSA::Heap::Memento")) {

		    my $id = $$$obj;

		    $$obj = undef;
			(DEBUG > 1) && print STDERR "Heap: setting up Data::Lazy($id)\n";
		    tie($$obj, 'Data::Lazy',
			sub {
			    DEBUG && print STDERR "Heap: loading object $id\n";
			    $storage->load($id);
			}, $obj);

		} elsif ($seen->insert($$obj)) {
		    push @obj_stack, $$obj;
		}
	    }
	}
    }
 
}

sub DESTROY {
    my $self = shift;
    $self->flush if tied(%{$self->get_session_h});
}

=head2 B<$heap-E<gt>hits()>

Returns the number of times that this session has been loaded

=cut

sub hits {
    my $self = shift;
    return $self->get_session_h->{hits};
}
*get_hits = \&hits;


=head2 B<$heap-E<gt>rollback()>

Forgets all of the changes to the heap and restores it to the way it
was the last time it was read.

=cut

sub rollback {
    my $self = shift;
    my $session_obj = tied %{$self->get_session_h};
    DEBUG &&
    print STDERR "PSA::Heap[$$]: rollback ".$self->sid."\n";

    # set flags that will stop the session being flushed when it is
    # untied.
    $session_obj->make_old;
    $session_obj->make_undeleted;
    $session_obj->make_unmodified;

    # re-attach; this will effectively discard $self, so get an
    # explicit reference to the PSA object
    my $psa = $self->psa;

    # Bugger, I get `untie attempted while 1 inner references still
    # exist' - back to DB sessions!
    #$psa->detach_heap();
    #$psa->attach_heap();

}
*get_hits = \&hits;

=head2 B<$heap-E<gt>commit($storage)>

Saves a session, but keeps it available.

=cut

use Storable qw(dclone);

sub commit {
    my $self = shift;
    my $storage = shift;
    DEBUG > 2 &&
	print STDERR "PSA::Heap[$$]: PSA->Heap->commit($storage)\n";

    $self->flatten($storage) if $storage;
    my $session_copy = dclone({%{ $self->get_session_h }});
    $self->flush();
    $self->set_session_h($session_copy);
    $self->psa->set_heap($self->get_session_h->{heap});
    $self->unflatten($storage) if $storage;

}

=head1 TO-DO

   * A PSA::Pixie equivalent of storage / heap / etc

=head1 AUTHOR

Sam Vilain, <sam@vilain.net>

=cut

1;
