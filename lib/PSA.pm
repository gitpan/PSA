#!/usr/bin/perl -w

package PSA;
use strict;
use Carp;

=head1 NAME

PSA.pm - Perl Server Applications

=head1 SYNOPSIS

See L<PSA::Intro> for a quick introduction to PSA, from an application
developer's and system administrator's viewpoint.

See L<bin/psa> for information on how to start PSA applications with
the command-line C<psa> utility.

See L<PSA::All> for information on starting arbitrary PSA applications
on system startup, and monitoring their use via a system such as
Nagios.

=head1 DESCRIPTION

Perl Server Applications are a fast and scalable solution to dynamic
page generation and general purpose application servers.

A C<PSA> object represents a request processor; instances of are
created for individual requests.  It has methods of accepting requests
(L<PSA::Acceptor>-derived objects), that emit request objects
(L<PSA::Request>-derived objects).  PSA pages, like small CGI extract
information from the request, do whatever they need to do with
storage, commit and then respond by passing some form of a
L<PSA::Response> object (possibly mutating it to a
L<PSA::Response::Template>).

Systems like ASP use global variables to represent some of the objects
that are properties of the C<PSA> object.

There are many other parts of the PSA object that come into play, see
below for details.

=head1 ATTRIBUTES

These are the attributes of the psa object.

=over

=item request

a PSA::Request derived object.  See L<PSA::Request>, though most
people will be interested in L<PSA::Request::CGI>.

=item response

a PSA::Response derived object.  See L<PSA::Response>, though most
people will be interested in L<PSA::Response::HTTP>.

=item session

database-held, schema driven session data.  See L<PSA::Session>.

=item heap_obj

object behind heap (may or may not bear some relation to
C<tied($psa-E<gt>heap)>, if set).  See L<PSA::Heap>.

=item heap

session-file or database-held, free form session data.  This is always
an application scratchpad, available no matter whether ACID sessions
(see L<PSA::Session>) or locking-style sessions (see L<PSA::Heap>) are
in use.

=item cache

the PSA::Cache object; responsible for efficiently calling other parts
of the application.  eg, when you need to "run" other pages, this
happens through C<$psa-E<gt>cache-E<gt>run()>.  See L<PSA::Cache>.

=item schema

The `Schema' object(s) for the application(s) currently housed by this
PSA instance.  This is normally a T2::Schema object; see L<T2::Schema>
for more.

=item storage

The Tangram::Storage (or, perhaps, T2::Storage) object(s) for the
application(s) currently housed by this PSA instance.  See
L<Tangram::Storage> and/or L<T2::Storage>.

=item sid

The Session ID of this PSA session.  This is normally a 32 letter hex
string (md5sum style).  Usually auto-generated or auto-slurped from
the request object.

=item docroot

Where on the local filesystem that "/" appears to be.  Auto-detected.

=item mileage

How many requests this particular instance of the Perl Server
Application has served.

=back

=cut

use base qw(Class::Tangram);
use vars qw($schema $VERSION);

$VERSION = "0.49_01";

# for user-space threading, a thread number
our $thread = 0;

$schema =
    {
     fields => {
		transient =>
		{
		 # "heap" - this is put into the flat session or
		 # session->data
		 heap => { init_default => {} },
		 sid => {
			 check_func => sub {
			     ${$_[0]} =~ m/^[0-9a-f]+$/i
				 or die "SID `${$_[0]}' bad";
			 },
			},
		 docroot => {
			     check_func => sub {
				 ( -d ${$_[0]} && -x _ )
				     or die "docroot ${$_[0]} not "
					 ."found or access denied";
			     },
			    },
		 # how many levels of running we are deep
		 run_depth => { init_default => 0 },
		 # pending states to run, with arguments (LoLoL)
		 run_queue => { init_default => [ ] },
		},
		string => {
			   entry_point => undef,
			  },
		int =>
		{
		 mileage => undef,
		 heap_open => undef,
		 threadnum => { init_default => 0 },
		},
		ref => {
			# these class settings are comments, really
			config   => { class => "PSA::Config" },
			cache    => { class => "PSA::Cache" },

			acceptor => { class => "PSA::Acceptor" },
			request  => { class => "PSA::Request" },
			response => { class => "PSA::Response" },

			session  => { class => "PSA::Session" },
			heap_obj => { class => "PSA::Heap" },

			storage  => { class => "Tangram::Storage" },
			schema   => { class => "T2::Schema" },
			# lexicon?
		       },

		# additional data stores, per site.
		hash => {
			 stores  => { class => "Tangram::Storage" },
			 schemas => { class => "T2::Schema" },
			},
	       }
    };

our $DEBUG = 0;
sub _say {
    print STDERR __PACKAGE__.": @_\n" if $DEBUG;
}

=head1 IMPORTER ARGUMENTS

By specifying a list of partial modules to load, make the code look
tidier;

  use PSA qw(Acceptor::AutoCGI Request::CGI Response::HTTP);

or, if using C<PSA::Init>:

  use PSA qw(Init);

this will load config and other things.

=cut

sub import {
    my $self = shift;

    my $package = (caller())[0];

    my @failed;
    foreach my $module (@_) {
	my $code = "package $package; use PSA::$module;";
	eval($code);
	if ($@) {
	    warn $@;
	    push(@failed, $module);
	}
    }

    @failed and croak "could not import qw(" . join(' ', @failed) . ")";

}

=head1 METHODS

=over

=item C<$psa-E<gt>run("page.psa", [@args])>

Runs "page.psa", passing @args as parameters.  You don't need to pass
the PSA object as the first parameter; this is automatic.

=cut

sub run {
    my $psa = shift;
    my $filename = shift;
    croak "type mismatch" unless ($psa->isa("PSA"));

    local ($psa->{running}) = $filename;

    _say "running $filename(@_)" if $DEBUG;

    {
	$psa->{run_depth}++;
	if (wantarray) {
	    my @rv = $psa->{cache}->run($filename, $psa, @_);
	    $psa->_run_queued;
	    $psa->{run_depth}--;
	    return @rv;
	} else {
	    my $rv = $psa->{cache}->run($filename, $psa, @_);
	    $psa->_run_queued;
	    $psa->{run_depth}--;
	    return $rv;
	}
    }
}

sub get_run_queue {
    my $psa = shift;

    my $depth = $psa->{run_depth};
    $#{$psa->{run_queue}} = $depth;

    return $psa->{run_queue}[$depth] ||= [];

}

=item $psa->yield("state", args);

Like ->run(), but calls the page I<after> this PSA has reached the top
of its call stack.

=cut

sub yield {
    my $self = shift;
    (my $state = $self->{running}) =~ s{[^/]*(\.[^/]*)$}{(shift).$1}e;
    unshift @_, $self, $state;
    push @{ $_[0]->run_queue }, \@_;
}

=item C<$psa-E<gt>spawn(@options)>

Like ->run(), but calls the page I<after> this page has finished, and
with a I<new> PSA object, which is a I<copy> of this one.  C<@options>
is passed to the copy constructor.

=cut

sub spawn {
    my $self = shift;
    my $copy = $self->new(heap => {%{$self->heap}}, run_depth => 0, @_);

    push @{ $self->run_queue }, [ $copy, $copy->entry_point||"whassap" ];
    return $copy;
}

sub set_threadnum {
    my $self = shift;
    $self->SUPER::set_threadnum($thread++);
}

#---------------------------------------------------------------------
#  _run_queued
# Dispatches all pages run via $psa->yield()
# This is a no-op in the POE runtime, as the pages are queued
# `immediately' as POE events
#---------------------------------------------------------------------
sub _run_queued {
    my $self = shift;
    #print STDERR "PSA $self; dispatching queued events\n";
    while (my $state = $self->_next_state ) {
	#print STDERR "PSA $self; dispatching @$state\n";
	last unless @$state;
	$state->[0]->run(@{$state}[ 1..$#$state ]);
    }
}

#---------------------------------------------------------------------
#  _next_state()
# Returns the next thing off the run queue of yielded pages, and if
# there is nothing left - returns the list of events that are waiting
# for this PSA to be done.
# ---------------------------------------------------------------------
sub _next_state {
    my $self = shift;

    if (my $next = shift @{ $self->run_queue }) {
	return $next;
    } elsif ($self->{done_queue} and $next = shift @{ $self->{done_queue} }) {
	return $next;
    }
}

=item C<$psa-E<gt>wait($child_psa, $state, @args)>

Lets the PSA object $child_psa know that you're waiting for it to
finish.  When it's done, and anything it's yielded, etc, are also
done, then it will signal completion by calling the passed state on
C<$psa>.

ie, this will call on completion:

  $psa->run($psa->rel_path($state), @args)

Note: using the POE runtime, this only works if C<$psa> is the parent
of C<$child_psa> as created using C<$psa-E<gt>spawn()>.

=cut

sub wait {
    my $self = shift;
    my $child = shift;
    (my $state = $self->{running}) =~ s{[^/]*(\.[^/]*)$}{(shift).$1}e;
    unshift @_, $self, $state;
    #print STDERR "Sending post_on_done(@_) to child $child\n";
    $child->_post_on_done(@_);
}

sub _post_on_done {
    my $self = shift;
    push @{ $self->{done_queue}||=[] },
	\@_;
}

=item B<$psa-E<gt>closure("page.psa", [@args])>

Returns an anonymous subroutine to "page.psa" compiled into a sub.

the sub is basically

 {
   my @args = (@_);
   my $psa
   sub {
      $psa->run("page.psa", @args, @_);
   }
 }

ie, the PSA object you construct it with becomes a default parameter
to it.

    my $widget = $psa->closure("mywidget.psa");

    $psa->include("mypagewithawidgetasaparameter.psa", $widget);

=cut

sub closure {
    my $psa = shift;
    my $filename = shift;
    (my @args, @_) = (@_);

    return sub { $psa->run($filename,@args,@_) }
}

=head2 B<$psa-E<gt>get_session>

Returns the PSA::Session object for this PSA instance.  Automatically
connects the session if no Heap/Session is open, so be careful :)

=cut

sub get_session {
    my $self = shift;
    UNIVERSAL::isa($self, "PSA")
	    or confess "method called as function";

    if (my $x = $self->SUPER::get_session()) {
	return $x;
    } elsif ($self->heap_open) {
	return undef;
    } else {
	$self->attach_session(shift);
	my $x = $self->SUPER::get_session();
	#print STDERR "Returning: $x\n";
	return $x;
    }
}

=head2 B<$psa-E<gt>sid>

Returns the session ID as a string.  The SID of the Session/Heap takes
priority over any SID received in the input request (they should be
the same of course :-))

Returns C<undef> if there is no SID already.  Generally the Session
constructor should set up the SID in the PSA object.

=cut

sub get_sid {
    my $self = shift;

    my $sid;
    if (!($sid = $self->SUPER::get_sid())) {

	if ( $self->heap_open ) {

	    my $heap = $self->get_heap_obj || $self->get_session;

	    if ($sid = $heap->get_sid) {
		return $sid;
	    }
	}
	my $req;
	if (($req = $self->get_request) and
	    ($sid = $req->get_sid)) {
	    return $sid;
	}
    }
    return $sid;
}

sub set_sid {
    my $self = shift;
    my $value = shift;

    $self->SUPER::set_sid( $value );

    # we set this in the request, as it is the request that next page
    # urls are generated against.
    if ( my $r = $self->get_request ) {
        $r->set_sid($value);
    }
}

=head2 B<$psa-E<gt>storage([ $site ])>

Returns the currently primary Tangram::Storage object, or the one for
the named site if given.

All connection details, as well as the file where the Tangram Schema
can be found, are stored in files in the web root in F<etc/>.

=cut

sub get_storage {
    my $self = shift;
    my $site = shift;

    if (defined($site)) {

	my $storage = $self->SUPER::get_storage();

	return $storage
	    if ($storage and $storage->get_site_name eq $site);

	eval {
	    $self->stores_insert
		($site => ($storage = T2::Storage->open($site)));

	    # link up the schema to the storage if it's there
	    if (my $schema = $self->get_schemas($site)) {
		$schema->set_storage($storage);
	    }
	} unless ($storage = $self->get_stores($site));

	return $storage;

    } else {
	return ($self->SUPER::get_storage());
    }
}

# force this accessor to always mean get
sub storage {
    my $self = shift;
    return $self->get_storage(@_);
}

=head2 B<$psa-E<gt>schema([ $site ])>

Returns the currently active T2::Schema object for the currently
running PSA site.  Note that this is a `T2::Schema' object, not a
`Tangram::Schema' object; the Tangram::Schema object can be retrieved
using $schema->schema ($psa->schema->schema).

=cut

sub get_schema {
    my $self = shift;

    my $site = shift;
    if (defined($site)) {

	my $schema = $self->SUPER::get_schema();

	return $schema
	    if $schema and $schema->get_site_name eq $site;

	eval {
	    $self->schemas_insert
		($site => ($schema = T2::Schema->read($site)));

	    # link up the schema to the storage if it's there
	    if (my $storage = $self->get_stores($site)) {
		$storage->set_schema($schema);
	    }

	} unless ($schema = $self->get_schemas($site));

	return $schema;

    } else {
	return $self->SUPER::get_schema();
    }

}

sub schema {
    my $self = shift;
    return $self->get_schema(@_);
}

=head2 B<$psa-E<gt>uri(...)>

Returns a URI to the next page.  Delegated to PSA::Request->uri, but
this is the primary method called by the default templates.

=cut

sub uri {
    my $self = shift;
    return $self->get_request->uri(@_);
}

=head2 B<$psa-E<gt>filename($pkgspace)>

Returns the PSA filename associated with the Perl package space
$pkgspace (as probably returned by a function like B<caller()>.

This is a PSA::Cache reverse lookup!

=cut

sub filename {
    my $self = shift;
    my $pkg = shift;

    return $self->get_cache->filename($pkg);
}

=head2 B<$psa-E<gt>docroot_ok($filename)>

Returns the local relative or absolute path to the passed relative
docroot location.

Should only return a path if the file is found to exist.

This function is used by the default/fallback templates that serve
static content (sometimes handled by PSA applications in the interest
of configuration flexibility).

=cut

sub docroot_ok {
    my $self = shift;
    my $filename = shift;

    # Hardcoded (in)sanity - don't let them see temp files or backups
    return undef if ( $filename =~ m{ (   \.(old|orig|bak|rej|tmp)
				      |   ~          # emacs backups
				      |   (^|/)CVS(/.+)?  # CVS dirs
				      |   ^\.\043.*  # emacs swap files
				      |   ^\.ht.*    # apache config
				      )$ }x );

    # Remove all `/../' components and affix "/"
    $filename =~ s{/?\.\./}{/}g;
    $filename =~ s{^([^/])}{/$1};

    # Prepend our docroot
    $filename = $self->docroot . $filename;

    # check file exists and return
    return ( -f $filename && -r _ ) ? $filename : undef;
}

=head2 B<$psa-E<gt>attach_session>

Starts the session via PSA::Session (database-side sessions).

If the C<$psa-E<gt>config> property is correctly configured, the class
of the Session can be overridden with the following F<etc/psa.yml>
fragment:

 classes:
   session: Your::Session

=cut

sub attach_session {
    my $self = shift;
    my $inv = (shift) || $self->class("session");
    $self->detach_heap if ref($inv) and $self->heap_open;

    return if $self->heap_open;
    my $session = ref($inv) ? $inv : undef;
    _say "ATTACHING ".($session?"":"(NEW) ")."SESSION";

    $self->set_session($session ||=
                       $inv->fetch($self->storage, $self->sid));

    $self->set_sid($session->get_sid);
    $self->set_heap($session->get_data);
    $self->set_heap_open(1);
}


our %dc = ( session => "PSA::Session" );
sub class {
    my $self = shift;
    my $type = shift;

    my $sc;
    if ( my $cfg = $self->get_config ) {
	if ( my $cl = $cfg->{classes} ) {
	    $sc = $cl->{$type};
	}
    }

    return $sc || $dc{$type};
}

=head2 B<$psa-E<gt>attach_heap>

Starts the session via PSA::Heap (middleware sessions).

=cut

sub attach_heap {
    my $self = shift;

    return if $self->heap_open;

    $self->set_heap_obj(PSA::Heap->new($self, @_));
    $self->set_heap_open(1);
}

=head2 B<$psa-E<gt>detach_heap>

Saves the session via PSA::Heap.

=cut

sub detach_heap {
    my $self = shift;

    return unless $self->heap_open;
    if ($self->heap_obj) {
	$self->heap_obj->flush();
    } else {
	$self->storage->update($self->get_session);
	$self->set_heap(undef);
    }
    $self->set_heap_open(0);
    $self->set_heap_obj(undef);
}

sub detach_session {
    my $self = shift;
    return $self->detach_heap(@_);
}

=head2 E<$psa-E<gt>rollback_heap>

Forgets all of the changes to the heap and restores it to the way it
was the last time it was read, or written.  ie, it's fetched again.
You better not have any remaining references to the main session
object, otherwise nothing will happen...

=cut

sub rollback_heap {
    my $self = shift;

    return unless $self->heap_open;
    if ($self->heap_obj->isa("PSA::Session")) {

	# we don't need to ROLLBACK; we can just re-load from the
	# consistent read snapshot.
	$self->abort_session;
	$self->attach_session;

    } else {
	$self->heap_obj->rollback;
    }
    $self->set_heap_open(0);
}

sub rollback_session {
    my $self = shift;
    return $self->rollback_heap(@_);
}

sub abort_session {
    my $self = shift;
    my $session = $self->get_session;

    $self->set_session(undef);
    $self->set_heap(undef);
    $self->set_heap_open(undef);

    $self->storage->unload($session);
    $session->clear_refs;
}

=head2 B<$psa-E<gt>commit_heap>

Saves the session, but keeps its data available.  The session is from
that point on, read-only.

=cut

sub commit_heap {
    my $self = shift;
    my $skip_storage = shift;
    return unless $self->heap_open;

    if ($self->get_heap_obj) {

	$self->heap_obj->commit($skip_storage ? () : $self->storage);

    } else {

	$self->storage->update($self->get_session);
    }

    $self->set_heap_open(0);
}

sub commit_session {
    my $self = shift;
    return $self->commit_heap(@_);
}


Class::Tangram::import_schema(__PACKAGE__);

42;

=head1 AUTHOR

Sam Vilain, <samv@cpan.org>

=cut

