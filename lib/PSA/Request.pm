
package PSA::Request;

=head1 NAME

PSA::Request - Encapsulate a generic PSA request.

=head1 SYNOPSIS

  my $acceptor = PSA::Acceptor::SomeType->new();

  my $request = $acceptor->accept();

  # fetch request meta-data; this might be headers in a SOAP
  # request, or CGI parameters.
  print $request->param("foo");

  # The request contains a unique, cryptographically strong
  # identifier.  Return it.
  print $request->sid();

  # The request has an associated URL.  With a CGI request,
  # this would be the request URL.  With a SOAP request, it
  # would be the soapmethod/soapaction
  print $request->uri();   # or ->url(), take yer pick

  # if the request was proxied in a way that we could detect,
  # the details will be here.
  print $request->proxy();  # like caller(); pass a number
                            # to go back N levels

  # Get the actual content... this method will possibly be
  # indexed in some manner, if the request supports
  # multi-part requests.
  print $request->body();

=head1 DESCRIPTION

B<PSA::Request> is an I<abstract base class>, that defines an
I<interface> for code to access information about B<incoming>
requests.

As such, the methods in this module that define how to return
information about the request are stubs that B<throw exceptions>, and
therefore B<must be defined in sub-classes> to be called.

Most users are more interested in the sub-classes of this module, such
as B<PSA::Request::CGI>, B<PSA::Request::XML> and
B<PSA::Request::SOAP>.  Go see the most relevant manual page for those
modules if you want to use a B<PSA::Request> object.

People who are writing new types of requests for their application
server will want to implement the interface described in this manual
page.

=cut

=head1 DATA MEMBERS

Certain aspects of input requests don't vary an awful lot between
request types.  These are defined as data members of the base class.
As such, they have accessors as provided by Class::Tangram (see
L<Class::Tangram>).

=over

=item sid

A unique identifier for this request.

Subclasses should explictly fill this variable when they are
constructed, if appropriate.  After the session is attached, the value
might be changed, if the SID in the request was invalid.

=item uri

This Identifes the Resource that this request is requesting in a
Universal manner.  It is the most specific part of the resource; eg,
once a message has been decoded from an envelope B<PSA::Request>
object to a more specific B<PSA::Request> object, this might change.

=back

=cut

use strict;
use Carp qw(cluck croak confess);
use warnings;

use base qw(Class::Tangram Exporter);
use Date::Manip qw(ParseDate);

our $schema =
    {
     abstract => 1,
     fields =>
     {
      string => { sid => { sql => "CHAR(32)" },
		  uri => { sql => "VARCHAR(255)",
			   check_func => sub { },
			 },
		},
      dmdatetime => {
		     received => { init_default => sub {
				       ParseDate("now")
				   } },
		    },
     },
    };

BEGIN {
    our @EXPORT_OK = qw($DEFAULT_SID_RE);
}

our $DEFAULT_SID_RE = qr/[0-9a-f]{12,32}/i;

=head1 METHODS

=head2 CONSTRUCTOR

=over

=item C<Class-E<gt>new()>

The standard B<new()> constructor should function as per the
Class::Tangram standard [ ie, C<(attribute =E<gt> $value, [...])> ].

=item C<Class-E<gt>fetch()>

In programming environments where the request is poked into strange
places in the process environment or other such mallarky, this method
should immediately fetch it all out, and not return until the request
has been fully encapsulated.

=back

=head2 METHODS

Not all of these methods apply to all types of request.

=over

=item C<$request-E<gt>param("name" [, "name" [...])>

Fetch a named parameter (or list of named parameters) to the request.
These are typically from the standard source of metadata for the given
request type, such as CGI form parameters, extra HTTP headers, etc.

=cut

sub param {
    my $self = shift;
    die("Request type ".ref($self)." doesn't know how to return a "
	."param!");
}

=item C<$request-E<gt>proxy([ $level ])>

This method should return either:

=over

=item *

An appropriate string that identifies a gateway URL, such as the POST
url for a SOAP gateway.

=item *

The "parent" B<PSA::Request> object.  Which I<should> stringify to a
URL, if only for easy debugging purposes.

=back

=cut

sub proxy {
    my $self = shift;
    die("Request type ".ref($self)." doesn't know how to return its "
	."proxy!");
}

=item C<$request-E<gt>body([ $index ])>

When called in scalar context with no arguments, this method I<must>
return the B<first> or B<primary> body of the message, before any kind
of decoding has been applied.

When called in list context with no arguments, this method I<should>
return B<all> parts, in order.

When called with a I<numeric> index, this method should return the
body part corresponding to that index in a multi-part message, or
I<undef>.

When called with a I<string> index, this method should return the body
part with that label in a multi-part message, or I<undef>.

This method B<must> return plain strings, which are complete
serialisations of the relevant body parts.

=cut

sub body {
    my $self = shift;
    die("Request type ".ref($self)." doesn't know how to return its "
	."body!");
}


1;

=back

=cut

