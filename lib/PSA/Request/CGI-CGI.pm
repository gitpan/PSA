
# this is an old version of the PSA::Request::CGI module, that uses
# the legacy CGI.pm module.

package PSA::Request::CGI;

use strict;

=head1 NAME

PSA::Request::CGI - Encapsulate a Cursed Gateway Interface Request

=head1 SYNOPSIS

 my $request = PSA::Request::CGI->fetch();

 my $sid = $request->sid;
 my $momma = $request->param("momma");

 my $login_name = $request->cookie->{"login_name"}->value();

 my $uri = $request->uri();

=head1 DESCRIPTION

This module decodes CGI requests into an encapsulated object, and
provides functions for convenient session management.

=cut

# Apologies for the colourful nature of the comments and documentation
# for this class.  It's not so much that it was hard to write, it's
# just that the hack commonly known as CGI has always caused me much
# pain, and writing this module is like dragging all of that pain out
# at once.  I hope once this module is finished the pain will be gone.

use base qw(PSA::Request);

use vars qw($DEFAULT_SID_RE);
BEGIN {
    PSA::Request->import qw($DEFAULT_SID_RE);
}

{
    package Fuck::Off::CGIpm::You::Suck;
    use CGI qw(:standard);
    use CGI::Cookie;
}

use vars qw($schema);

use Maptastic;

use constant STANDARD_CGI_HEADERS =>
    qw(server_software gateway_interface server_name server_protocol
       server_port request_method path_info path_translated
       script_name query_string remote_host remote_addr auth_type
       remote_user remote_ident content_type content_length
       http_referer); # http_referer is not part of the CGI spec

$schema =
    {
     table => "http_requests",
     bases => [ qw(PSA::Request) ],
     fields =>
     {
      # all "idbif" columns are stored as one perl_dump
      idbif => {
		env => { init_default => sub { return {%ENV} },
		       },

		# The CGI cookies of this request
		cookies => { sql => "BLOB", },
		param => { sql => "BLOB", },

		# `base' path for uris
		base => { init_default => "" },

       # create simple dumb accessors
       map {( $_ => undef )} (STANDARD_CGI_HEADERS,
	  qw(query_sid cookie_sid path_sid sid_re sid_query_param
	     cookie_name))
		   },
      transient =>
      {
       # for auxilliary access to the CGI object and environment
       cgi => undef,

      },
     },
    };

Class::Tangram::import_schema(__PACKAGE__);

=head1 METHODS

=head2 fetch(option => value, [...])

This is the main constructor for PSA::Request::CGI objects.

This function extracts all the standard CGI globals from the
environment, and extracts the session ID from a variety of places, as
described above.

Available options:

=over

=item env

The environment to extract information out of.  Defaults to the
program environment (C<%ENV>).

=item fh

The filehandle to read POST and PUT data from.  Defaults to standard
input.

=back

=cut

sub fetch($@) {
  (my ($class, %options), @_) = (@_);

  my $fh = delete $options{fh};
  my $self = $class->new(%options);

  # get the standard headers out and leave the rest behind
  $self->set( map { ((exists $self->{env}->{uc($_)}) ?
		     ($_ => $self->{env}->{uc($_)}) : () ) }
	      STANDARD_CGI_HEADERS );

  # perhaps PATH_INFO is not set, in which case, move it from SCRIPT_NAME
  $self->set_path_info($self->script_name),
      $self->set_script_name("/")
	  unless exists $self->{env}->{PATH_INFO};

  # better be a CGI request
  $self->{gateway_interface} ||= "CGI/1.1";  # for interactive
  ($self->{cgi_version}) =
      ($self->{gateway_interface} =~ m{CGI/(\d+(?:\.\d+)*)});
  die "Can't deal with gateway interface $self->{gateway_interface}"
      unless ($self->{cgi_version} and $self->{cgi_version} >= 1.1);

  map_each { $self->{$_[0]} = $_[1] unless defined ($self->{$_[0]}) }
      ({ server_name => "localhost",
	 script_name => "/$0",
	 server_protocol => "HTTP/1.0" });

  # ARGH!! CGI.pm still has to be used for mod_perl to work!!!
  # we also can't get rid of it until we can parse posted forms.

  # save the environment, because CGI.pm isn't capable of reading all
  # of its input variables via its function arguments.
  {
      my %ENV_SAVE=%ENV;
      %ENV = %{$self->{env}};
      use Data::Dumper;

      CGI::initialize_globals();

      $self->{cgi} = new CGI ($fh||());

      # put the passed (posted, query_string) parameters into
      # $self->{param}
      $self->{param} = {};
      for my $param ($self->{cgi}->param) {
	  $self->{param}->{$param} = [ $self->{cgi}->param($param) ];
      }

      # fetch cookies
      $self->{cookies} = { CGI::Cookie->fetch };

      %ENV=%ENV_SAVE;
  }
  delete $self->{env}{$_} foreach qw(STANDARD_CGI_HEADERS);

  $self->_get_sid();

  return $self;
}

=head2 param("name" [, "name" [...])

Fetch a named parameter (or list of named parameters) to the request.

Setting the same CGI parameter multiple times within the same query
string (eg C<http://www.foo.com/script.cgi?yin=empty&yin=without>) is
possible, but not advised.  If you want to get them out, then make
sure you call param in list context and exactly one parameter name.

=cut

# F***ING CGI.pm!!  It always exports "param", no matter what.  So
# this spits out a warning "function param redefined at..."
{
    no warnings 'redefine';
    sub param {
	my $self = shift;
	if ( @_ ) {
	    if ( wantarray ) {
		if ( @_ == 1 ) {

		    # special case ... allow all values of a parameter
		    # to be returned in list context with one
		    # parameter
		    my $param = shift;
		    if ( exists $self->{param}->{$param} ) {
			return @{ $self->{param}->{$param} }
		    } else {
			return ();
		    }
		} else {
		    return map { exists $self->{param}->{$_}
				     ? $self->{param}->{$_}->[0]
					 : undef } @_;
		}
	    } else {
		my $param = shift;
		if ( exists $self->{param}->{$param} ) {
		    return $self->{param}->{$param}->[0];
		} else {
		    return undef;
		}
	    }
	} else {
	    return keys %{$self->{param}};
	}
    }
}

=head2 filename()

Returns the PATH_INFO of this request, with the session ID and other
parameters removed.  Also, if present the BASE uri (as set by
C<$request-E<gt>set_base()>) is removed.

=cut

sub filename {
    my $self = shift;

    # decide what session IDs look like
    my $sid_re = $self->{sid_re} || $DEFAULT_SID_RE;

    my $path_info = $self->{path_info} or return "";
    $path_info =~ s!/$sid_re|^/(?=/)!!ig;
    $path_info =~ s!^$self->{base}!!
	if $self->{base};

    return $path_info;
}

sub set_base {
    my $self = shift;
    my $value = shift;

    # normalise //'s
    $value =~ s{^/*(.*?)/*$}{/$1};

    $self->SUPER::set_base($value);
}

sub dirname {
    my $self = shift;
    (my $path_info = $self->filename) =~ s{/?[^/]*$}{/};
    return $path_info;
}

sub basename {
    my $self = shift;
    (my $path_info = $self->filename) =~ s{.*([^/]*)$}{$1};
    return $path_info;
}

=head2 uri("option" [,...])

This returns a URI suitable for using in links and form targets.  If
given no parameters, it will return a string that takes you back to
the same page using relative links, which may or may not contain a
query component.

Specify any of the following keywords to modify the URI that is
returned:

=over

=item absolute

Ensures that the URI is complete - eg
C<http://hostname/script.cgi/page.pl>.

=item post

Ensures that the URI is suitable for POSTing.  This means there will
be no query component.  If we didn't get a valid SID from a cookie,
the SID will be placed in the path.

=item query

Ensures that the uri ends in a query component

=item flat

Specifies that the file is a flat resource; return a URL to what we
suppose is our docroot.

=item nosid

Don't try and encode the session ID in the URL.

=item self

Ensures that the uri points to yourself.  This is a default option.

=item C</\./>, or "call", "page.pl"

It is a URI to another page within PSA.  Specify the relative path to
that page as a parameter.  Any parameter containing a dot is assumed
to mean a link.

=back

=cut

use Data::Dumper;
use URI;

sub uri {
    my $self = shift;

    # read input options
    my %options;
    while ( my $option = shift ) {
	if ( $option =~ m/^(call)$/i ) {
	    $options{$1} = shift;
	}
	elsif ( $option =~ m/[^a-zA-Z]/ ) {
	    $options{call} = $option
	}
	else {
	    $options{$option} = 1;
	}
    }

    # build a uri to self - FIXME - check this works with SSL
    my $uri_self = URI->new();
    (my $trimmed_protocol = $self->{server_protocol}) =~ s{/.*}{};
    $uri_self->scheme($trimmed_protocol);
    $uri_self->host($self->{server_name});
    $uri_self->port($self->{server_port});              # (URI.pm)++
    my $pi = $self->{script_name}.($self->{path_info}||"");
    $pi =~ s{^//+}{/};
    $uri_self->path($pi);
    #$uri_self->query($self->{query_string});

    # build a uri for the hit they want
    my $uri_next = $uri_self->clone();
    # this is what will probably be different
    my ($path_info, $query_string);

    if ($options{flat}) {

	my $path = $self->{script_name};

	# this sorta relies on the base being detected correctly.
	$path = ($self->{base}||"")."/$options{call}";

	$path =~ s{^/*}{/};
	$uri_next->path($path);

    } else {
	# get the filename of this request without the SID
	$path_info = ($self->filename() || "");

	$path_info =~ s{^([^/])}{/$1};
	if ($options{call}) {
	    if ($options{call} =~ m{^/}) {
		$path_info = $options{call};
	    } else {
		# set the page they want, otherwise point to self
		$path_info =~ s{^(.*?)(/[^/]*)?$}{$1/$options{call}}
	    }
	}

	# did we get a SID cookie?
	my $got_sid_cookie = ($self->{cookie_sid} and
			      $self->{cookie_sid} eq $self->{sid});

	unless ( $options{nosid} or !$self->{sid} ) {
	    if ( $options{post} ) {
		$path_info =~ s{/|^}{/$self->{sid}$&}
		    unless $got_sid_cookie;
	    } else {
		$query_string = "SID=$self->{sid}"
		    unless $got_sid_cookie;

		if ( $options{query} ) {
		    $query_string = ($query_string ? "$query_string&" : "");
		}
	    }
	}

	# set the path and query string for the next uri
	($pi = ($self->{base}||"").$self->{script_name}.$path_info) =~ s{//+}{/}g;
	$pi =~ s{^$self->{base}$self->{base}}{$self->{base}};
	$uri_next->path($pi);
	$uri_next->query($query_string);

    }

    # now, which uri do they want?
    if ( $options{absolute} ) {
	return $uri_next->canonical();
    } else {
	return $uri_next->rel($uri_self);   # (URI.pm)++
    }
}

sub referer {
    my $self = shift;
    return $self->http_referer;
}

# moved from PSA::Request::CGI so can share with PSA::Request::XML

sub _get_sid {
    my $self = shift;

    # decide what session IDs look like
    my $sid_re = $self->{sid_re} || $DEFAULT_SID_RE;

    # look in PATH_INFO
    if ( $self->{path_info}
	 and $self->{path_info} =~ m!/($sid_re)/!) {
	$self->{path_sid} = $1;
    }

    # and form parameters
    # FIXME - might have multiple SIDs in query params
    if ( my $sid = $self->param($self->{sid_query_param}
				|| "SID") ) {
	$self->{query_sid} = $sid
	    unless $sid !~ m!^($sid_re)$!;
    }

    # and cookies
    # FIXME - might have multiple cookies (IE4!)
    if ( my $cookie = $self->{cookies}->{$self->{cookie_name}
					 || "SID" }) {

	for my $sid ( $cookie->value() ) {
	    next unless $sid =~ m/^$DEFAULT_SID_RE$/;
	    $self->{cookie_sid} = $sid;
	    last;
	}
    }

    $self->{sid} = ($self->{path_sid} ||
		    $self->{query_sid} ||
		    $self->{cookie_sid});
}

"nyarlethotep";

__END__

=head1 SESSION TRACKING

This module looks for session IDs in the following places when you
call C<fetch()>:

=over

=item HTTP Cookie

If there is a cookie called "SID", then that is taken to mean the
session ID.  If you want to call your cookie something else, see
L<cookie_name>.

=item PATH_INFO

The C<PATH_INFO> is often a handy place to put the SID.  It just
doesn't have the headaches of many other places, but of course you
lose the ability to cut and paste document URLs.  Caveat emptor.

To make it clear, the C<PATH_INFO> is everything after the name of the
script; that is, in this url:

  http://meat.shop/cgi-bin/script.cgi/1234/hello

Assuming that F</cgi-bin/script.cgi> refers to a valid CGI script,
then the C<PATH_INFO> will be C</1234/hello>.

For this to work, we have to know what session IDs look like.  Most
session ids are either a long string of numbers or hex digits, so I
use the regular expression C<qr/[0-9a-f]{12,32}/i> by default to mean
a session ID.  If your session ID does not match that regular
expression, you'll have to define the C<sid_re> attribute.

Note that this C<sid_re> regular expression is used to sanity check
all SIDs received.  If it doesn't match the expression, it is IGNORED.

=item QUERY_STRING

If there is a query parameter called "SID", then that is taken to mean
the session ID.  The attribute C<sid_query_param> overrides this.

=back

=head1 CGI ENVIRONMENT VARIABLES

Common Gateway Interface version 1.1 is defined at
http://hoohoo.ncsa.uiuc.edu/cgi/env.html; It defines (amongst other
arbitrary and crap things) some standard environment variables that
are passed to CGI programs.  Apache embraces and extends this list to
contain exotic bullshit environment variables useful for writing one
line shell scripts.  B<Do not be seduced by these environment
variables, they are as bad as not having `use strict' at the top of
your programs.>

This module deals with that rubbish for you.  It extracts all of the
information out of the environment and presents them as methods of the
request object.  This allows for the actual mechanism by which
requests come in to alter its form without you having to rewrite all
your scripts; they merely need implement an interface equivalent to
this one.

The following functions are defined for the nostalgic and impatient;
note that these are effectively carried over cruft from the CGI
specification; by using them, you are importing that crap directly
into your program.

Much better to use the functions above, which are more generic.

=over

=item server_software

The software that the web server is running - Software/version

=item gateway_interface

probably "CGI/1.1"

=item server_name

The server name that was used in the HTTP request

=item server_protocol

HTTP/1.1

=item server_port

80

=item request_method

GET, PUT, POST, etc.

=item path_info

Everything after the script name in the URL

=item path_translated

C<$0 . $path_info>

=item script_name

Everything up to the script name in the URL

=item query_string

Everything after the ? in the URL

=item remote_host

the other end of this connection

=item remote_addr

Remote IP address of the client

=item auth_type

??

=item remote_user

presumably the HTTP user name

=item remote_ident

?

=item content_type

The MIME content type of the input

=item content_length

The number of octets of the input

=item http_referer

The full URL of the referring page; this environment variable is not
officially part of the CGI spec, but it is usually set.

=back

=head1 AUTHOR

Sam Vilain, <perl@snowcra.sh>

=cut

