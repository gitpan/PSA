#    -*- cperl -*- mode rocks!

use strict;

=head1 NAME

PSA::Session - PSA persistent Session data

=head1 SYNOPSIS

 my $session = PSA::Session->fetch($storage, $sid);

 $session->data->{myStuff} = $stuff;

 # when done
 $storage->update($session);

=head1 DESCRIPTION

PSA::Session is for session-persistent state.  Note that the C<data>
hash can contain arbitrary references to other Tangram storage
objects.

=cut

package PSA::Session;

use strict;

use CGI::Cookie;

use Digest::MD5 qw(md5_hex);

use Carp;

use base qw(Class::Tangram);

#---------------------------------------------------------------------
#  Object Schema
#---------------------------------------------------------------------
our $schema = {
    table => "sessions",

    fields => {
	string => {
	    # MD5 session ID - really just a 32 letter random string
	    sid => { sql => "VARCHAR(32)" },

            # initial value of HTTP_REFERER; often useful
	    whence => undef,

	    # language
	    lang => { sql => "varchar(15)" },
	},

	# generic data store
	perl_dump => { data => { sql => "BLOB" } },

	int => {
	    # total count of page impressions, updated automatically
	    # on a fetch()
	    impressions => { init_default => 1 },
	},

	dmdatetime => {
	    # when this session object was created
	    created => undef,

	    # the last time this session object was accessed
	    lastused => { init_default => 0 },
	},

	transient => { is_new => undef,
		       since => undef,
		     },
    },
};

use Date::Manip qw(ParseDate DateCalc);

sub hit {
    my $self = shift;
    $self->set_lastused;
    $self->{impressions}++;
}


sub set_lastused {
    my $self = shift;
    my $val = ParseDate((shift) || "now");
    if ( my $old = $self->get_lastused ) {
	$self->set_since(DateCalc($old, $val));
    }
    return $self->SUPER::set_lastused($val);
}

=head1 CLASS METHODS

=over

=item B<PSA::Session-E<gt>fetch($storage, $sid)>

Loads a session from the $storage, or creates one.

C<$sid> is a Session ID to resume, if any

C<$storage> is a Tangram::Storage object that can contain PSA::Session
objects

=cut

sub fetch {
    my ($class, $db, $sid, $no_update) = (@_);
    $db or croak "no DB handle to put session in";
    $db->isa("Tangram::Storage") or croak "DB handle not a valid storage";

    # see if any sessions have the sid they gave
    if ($sid and $sid =~ m/^[a-f0-9]{32}$/) {
	my $rem = $db->remote($class);
	my ($session) = $db->select($rem, $rem->{sid} eq $sid);

	# if session is found, update the hitcount and lastused and
	# return.
	if ($session) {
	    $session->set_lastused();
	    $session->{impressions} ++;

	    return $session;
	}
    }

    # new session - set up a new object
    my $self = $class->create();

    # store it, so that `update' later is OK
    $db->insert($self);

    return $self;

}

=item B<PSA::Session-E<gt>create(@values)>

Creates a new session.

=cut

sub create {
    my($class, @values) = (@_);

    # call the Class::Tangram initialiser
    my $self = $class->SUPER::new(@values);

    $self->set_created( ParseDate("now") );

    # Assuming we get at least 16 bits of entropy out of each rand()
    # call, this should be OK.  Hopefully this should be more like 32
    # or even 64.
    $self->get_sid or $self->set_sid(do {
	my $entropy; for (1..8) { $entropy .= rand() }
	md5_hex($entropy);
    });

    # default to the "data" member being a hash reference
    $self->{data} ||= {};

    # set up some other values
    $self->{impressions} = 1;
    $self->{whence} = $ENV{HTTP_REFERER};
    $self->{lang} ||= "en_GB";

    $self->set_is_new(1);

    bless $self, $class;
    return $self;
}

sub hits {
    my $self = shift;
    return $self->get_impressions();
}
sub get_hits {
    my $self = shift;
    return $self->get_impressions();
}

sub fresh {
    my $self = shift;
    return $self->is_new;
}

42;

=back

