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

use base qw(PSA::Request);

use vars qw($DEFAULT_SID_RE);
BEGIN {
    PSA::Request->import qw($DEFAULT_SID_RE);
}

use vars qw($schema);

use Maptastic;

use constant STANDARD_CGI_HEADERS =>
    qw(server_software gateway_interface server_name server_protocol
       server_port request_method path_info path_translated
       script_name query_string remote_host remote_addr auth_type
       remote_user remote_ident content_type content_length
       http_referer); # http_referer is not part of the CGI spec

# note: memory size may be significantly larger than this before it is
# tripped, so pick a size that is suitably small.
our $POST_MAX = $ENV{CGI_POST_MAX} || 2 ** 14;   #16k
our $UPLOAD_MAX = $ENV{CGI_POST_MAX} || 2 ** 20; #1M
our $UPLOAD_DIR = $ENV{CGI_UPLOAD_DIR} || $ENV{TMP_DIR}
    || "/tmp";

our %request_defaults =
    (
     server_name => "localhost",
     gateway_interface => "CGI/1.1",
     script_name => "/$0",
     server_protocol => "HTTP/1.0",
     request_method => "GET",
    );

$schema =
    {
     table => "http_requests",
     bases => [ qw(PSA::Request) ],
     fields =>
     {
      # all "idbif" columns are stored as one perl_dump
      idbif => {

		# unparsed environment variables
		env => { init_default => sub { return {%ENV} },
		       },

		# The CGI cookies of this request
		cookies => undef,

		# url-encoded CGI parameters
		param => undef,
		# other post types (eg, XML)
		data => undef,

		# `base' path for uris
		base => { init_default => "" },

		# create simple dumb accessors for extra attributes
		(map {( $_ => ($request_defaults{$_}
			       ? { init_default =>
				   $request_defaults{$_} }
			       : undef) )}
		 (STANDARD_CGI_HEADERS,
		  qw(query_sid cookie_sid path_sid sid_re
		     sid_query_param cookie_name)))
	       },
      transient =>
      {
       fh => { init_default => sub { \*STDIN } },
       directory => undef,
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

  # get the standard headers out and leave the rest behind
  $options{env} = { $options{env} ? %{$options{env}} : %ENV };
  foreach ( STANDARD_CGI_HEADERS ) {
      if ( exists $options{env}{uc($_)} ) {
	  $options{$_} ||= delete $options{env}{uc($_)};
      }
  }

  my $self = $class->new(%options);

  $self->init();

  return $self;

}

sub init {
    my $self = shift;

    # perhaps PATH_INFO is not set, in which case, move it from SCRIPT_NAME
    unless (defined $self->path_info) {
	$self->set_path_info($self->script_name);
	$self->set_script_name("/");
    }

    # better be a CGI request
    ($self->{cgi_version}) =
	($self->{gateway_interface} =~ m{CGI/(\d+(?:\.\d+)*)});

    die "Can't deal with gateway interface $self->{gateway_interface}"
	unless ($self->{cgi_version} and $self->{cgi_version} >= 1.1);

    # setup the `self' URI
    my $uri_self = URI->new();
    (my $trimmed_protocol = $self->{server_protocol}) =~ s{/.*}{};
    $uri_self->scheme($trimmed_protocol);
    $uri_self->host($self->{server_name});
    $uri_self->port($self->{server_port});              # (URI.pm)++
    my $pi = $self->{script_name}.($self->{path_info}||"");
    $pi =~ s{^//+}{/};
    $uri_self->path($pi);
    $uri_self->query($self->{query_string}) if $self->{query_string};
    $self->set_uri($uri_self);

    # cookies are an environment variable, so we can parse those
    # straight away.
    $self->_eat_cookies();

    # parse query parameters, unless it's a POST (then they are defered
    # until needed)
    $self->_parse_form_quick();

    # try non-invasive methods of finding the SID
    $self->_get_sid_quick();

    return $self;
}

=head2 param("name" [, "name" [...])

Fetch a named parameter (or list of named parameters) to the request.

Setting the same CGI parameter multiple times within the same query
string (eg C<http://www.foo.com/script.cgi?yin=empty&yin=without>) is
possible, but not advised.  If you want to get them out, then make
sure you call param in list context and exactly one parameter name.

=cut

sub param {
    my $self = shift;
    $self->_parse_form() unless $self->{param};
    if ( @_ ) {
	if ( wantarray ) {
	    if ( @_ == 1 ) {

		# special case ... allow all values of a parameter
		# to be returned in list context with one
		# parameter
		my $param = shift;
		if ( exists $self->{param}{$param} ) {
		    return (ref $self->{param}{$param} eq "ARRAY"
			    ? @{ $self->{param}{$param} }
			    : $self->{param}{$param} );
		} else {
		    return ();
		}
	    } else {
		return map { (exists $self->{param}{$_}
			      ? ( ref $self->{param}{$_} eq "ARRAY"
				  ? $self->{param}{$_}[0]
				  : $self->{param}{$_} )
			      : undef
			     ) } @_;
	    }
	} else {
	    my $param = shift;
	    if ( exists $self->{param}{$param} ) {
		return ( ref $self->{param}{$param} eq "ARRAY"
			 ? $self->{param}{$param}[0]
			 : $self->{param}{$param} );
	    } else {
		return undef;
	    }
	}
    } else {
	return keys %{$self->{param}};
    }
}

sub get_param {
    my $self = shift;
    $self->_parse_form() unless $self->{param};
    return $self->SUPER::get_param(@_);
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

sub is_post {
    my $self = shift;
    return ($self->{request_method} =~ m/^(?:post|put)$/i);
}

sub is_postfile {
    my $self = shift;
    return ($self->is_post and
	    $self->content_type and
	    $self->content_type !~
	    m{(?:multipart/form-data|
	      application/x-www-form-urlencoded)}x);
}

sub get_sid {
    my $self = shift;
    if ( my $sid = $self->SUPER::get_sid ) {
	return $sid;
    } elsif ( ! $self->{param} ) {
	$self->parse_form;
	$self->_get_sid;
	return $self->SUPER::get_sid;
    } else {
	return $sid;
    }
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
    return $self->get_uri unless @_;

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

    # build a uri for the hit they want
    my $uri_next = $self->get_uri->clone();
    $uri_next->query_form([]);
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
	my $pi = $self->{script_name}.($self->{path_info}||"");
	($pi = ($self->{base}||"").$self->{script_name}.$path_info) =~ s{//+}{/}g;
	$pi =~ s{^$self->{base}$self->{base}}{$self->{base}};
	$uri_next->path($pi);
	$uri_next->query($query_string);

    }

    # now, which uri do they want?
    if ( $options{absolute} ) {
	return $uri_next->canonical();
    } else {
	return $uri_next->rel($self->get_uri);   # (URI.pm)++
    }
}

sub referer {
    my $self = shift;
    return $self->http_referer;
}

sub _get_sid_quick {
    my $self = shift;

    # decide what session IDs look like
    my $sid_re = $self->{sid_re} || $DEFAULT_SID_RE;

    # look in PATH_INFO
    if ( $self->{path_info}
	 and $self->{path_info} =~ m!/($sid_re)/!) {
	$self->{path_sid} = $1;
    }

    # and cookies
    # FIXME - might have multiple cookies (IE4!)
    if ( my $cookie = $self->{cookies}->{$self->{cookie_name}
					 || "SID" }) {

	for my $sid ( (ref $cookie ? @$cookie : $cookie) ) {
	    next unless $sid =~ m/^$DEFAULT_SID_RE$/;
	    $self->{cookie_sid} = $sid;
	    last;
	}
    }

    # and form parameters
    # FIXME - might have multiple SIDs in query params
    if ( $self->{param} &&
	 (my $sid = $self->param($self->{sid_query_param}
				 || "SID") )) {
	$self->{query_sid} = $sid
	    if $sid =~ m!^($sid_re)$!;
    }

    return ($self->{sid} ||= ($self->{path_sid} ||
			      $self->{query_sid} ||
			      $self->{cookie_sid}));
}

sub _get_sid {
    my $self = shift;
    $self->_parse_form unless $self->{param};
    $self->_get_sid_quick;
}

sub get_data {
    my $self = shift;
    $self->_parse_form unless $self->{param};
    return $self->SUPER::get_data(@_);
}

sub set_directory
{
    my ($self, $directory) = @_;

    stat ($directory);

    if ( (-d _) && (-e _) && (-r _) && (-w _) ) {
	return $self->SUPER::set_directory($directory);
    } else {
	return undef;
    }
}

sub browser_escape
{
    my $self = shift
	if (ref $_[0] and UNIVERSAL::isa($_[0], __PACKAGE__));

    my $string = shift;

    $string =~ s/([<&"#%>])/sprintf ('&#%d;', ord ($1))/ge;

    return $string;
}

sub url_encode
{
    my $self = shift
	if (ref $_[0] and UNIVERSAL::isa($_[0], __PACKAGE__));

    my $string = shift;

    $string =~ s/([^-.\w ])/sprintf('%%%02X', ord $1)/ge;
    $string =~ tr/ /+/;

    return $string;
}


sub url_decode {
    my $self = shift
	if (ref $_[0] and UNIVERSAL::isa($_[0], __PACKAGE__));

    my $string = shift;
    $string =~ tr/+/ /;
    $string =~ s/%([\da-fA-F]{2})/chr (hex ($1))/eg;

    return $string;
}

# split up a URL or cookie encoded string into a hash
sub _decode_url {
    my $self = shift
	if (ref $_[0] and UNIVERSAL::isa($_[0], __PACKAGE__));

    #my $data = shift;
    #my $is_cookies = shift;

    my $delimeter = ($_[1] ? qr/;\s+/ : qr/&/);

    my $bucket = {};
    return $bucket unless $_[0];

    while ( $_[0] =~ m/\G([^=]*)=((?:(?!$delimeter).)*)(?:$delimeter)?/sg ) {
	my ($key, $value) = ($1, $2);
	_add_param($bucket, url_decode($key), url_decode($value));
    }
    $bucket;
}

sub _add_param {
    my $self = shift if (ref $_[0] and UNIVERSAL::isa($_[0], __PACKAGE__));
    my $bucket = shift;
    my $key = shift;
    my $value = shift;
    if ( exists $bucket->{$key} ) {
	$bucket->{key} = [$bucket->{$key}] unless ref $bucket->{$key};
	push @{$bucket->{key}}, $value;
    } else {
	$bucket->{$key} = $value;
    }
}

sub _parse_form_quick {
    my $self = shift;
    $self->_parse_form unless $self->is_post;
}

# parse_form - slurps up the input form
sub _parse_form {
    my $self = shift;

    if ( $self->request_method =~ /^(get|head)$/i ) {
	# decode parameters from QUERY_STRING
	$self->{param} = $self->_decode_url($self->query_string);
    }
    elsif ( lc($self->request_method) eq "post" ) {

	my $content_type = $self->content_type ||
	    "application/x-www-form-urlencoded";

	if ( $content_type =~ m{multipart/form-data} ) {
	    $self->_slurp_multipart_data;
	} elsif ( $content_type eq "application/x-www-form-urlencoded") {
	    $self->_slurp_form_data;
	} else {
	    $self->_slurp_rpc_data;
	}
    }
    elsif ( lc($self->request_method)
	    =~ /^(options|put|delete|trace|connect)$/ ) {
	$self->{param} = $self->_decode_url($self->query_string);
    }
    else {
	# WebDAV?
	warn "Non-RFC2616 compliant HTTP method `"
	    .$self->request_method."' (uri = ".$self->uri.")";
    }
}

# parse and set up cookie information from HTTP_COOKIES env. var
sub _eat_cookies {
    my $self = shift;

    $self->set_cookies($self->_decode_url($self->http_cookie, 1));
}

our $AUTOLOAD;
sub AUTOLOAD {
    my $self = shift;
    $AUTOLOAD =~ s{.*::}{};
    return $self->{env}{uc($AUTOLOAD)};
}

our $READ_CHUNK_SIZE = 2 ** 12;

use IO::Handle;

sub _slurp_form_data {
    my $self = shift;
    my $is_file = shift;

    my $fh = $self->fh;

    my $buffer;
    my $upload_size = $fh->read($buffer, $POST_MAX);
    my $overflow;
    if ( $upload_size == $POST_MAX and $fh->read($overflow, 1) ) {
	die "413 POST too large"
    }

    if ( $is_file ) {
	$self->set_data($buffer);
	$self->set_param({});
    } else {
	$self->set_param(_decode_url($buffer));
    }
}

sub _slurp_rpc_data {
    my $self = shift;
    $self->_slurp_form_data(1);
}

# This really is something of a hack.  This routine is still not
# completely invulnerable to memory exhaustion attacks, and probably
# does not deal with a myriad of cases that it should.  But then,
# CGI::Lite itself performs about the same level of multipart form
# processing, so IMHO this is a good start.  A pity that MIME::Parser
# can't be used without a file handle wrapper module.

# The memory exhaustion attacks are probably relatively trivial to
# work around, using sanity checks on the number of headers/form
# variables, length of the boundary string (at the moment, a very long
# boundary string may cause quadratic performance penalties)

# the algorithm implemented here is designed so that it could easily
# be tied to module that implements out-of-core spooling of the input
# data, eg via any of the mmap() implementations out there.

sub _slurp_multipart_data {
    my $self = shift;

    my ($boundary) = ($self->content_type =~ m{boundary=(\S*)});

    my $breg = "(?s:.{".(length($boundary)+2).",})";
    $breg = qr/$breg/;

    my ($accum, $buffer, $item);
    $accum = "";
    my $state = 0;
    my $bytes_read = 0;
    my $part;
    my $param = {};
    my $fh = $self->fh;
 CHUNK:
    while ( my $upload_size = $fh->read($buffer, $POST_MAX) ) {
	die "413 POST too large"
	    if ($bytes_read += $upload_size > $UPLOAD_MAX);

	$accum .= $buffer;
	pos($accum) ||= 0;
    LINE:
	while ( pos $accum < length $accum ) {
	    # if a pattern doesn't match, the pos is lost, bummer.
	    my $oldpos = pos $accum;
	    if ( $state == 0 and  # between MIME parts
		 ($accum =~ m{\G(?: (--\Q$boundary\E(--)?\r?\n)
			      |      \s*\r?\n )}gx) ) {
		if ( $1 ) {
		    if ( $2 ) {
			$state = 3;
		    } else {
			$state = 1;
			$part = {};
		    }
		}
		else {
		    next LINE;
		}
	    }
	    elsif ( $state == 1 and # in MIME header
		    $accum =~ m{\G(?: ([\w\-]+):(?:\s+(.*))?\r?\n
				| (\s*\r?\n) )}gx) {
		if ( $1 ) {
		    # got a header
		    $part->{$1} = (defined($2) ? $2 : "");
		} else {
		    $state = 2;
		    # now, we have the entire header, so let's parse it.
		    my $cd = delete $part->{'Content-Disposition'}
			or die "400 Bad Request (no Content-Disposition)";

		    my $type = delete $part->{"Content-Type"};
		    ($type =~ s{[\r\n]*$}{}sg) if $type;

		    my ($name) = ($cd =~ m/name="(.*?)"/);
		    if ( my ($filename) = ($cd =~ m/filename="(.*?)"/ )) {
			$part = new PSA::Request::CGI::Upload
			    ( filename => $filename,
			      ($type ? (type => $type) : () ),
			      headers => $part,
			    );
			$param->{$name} = $part;
		    } else {
			$part->{name} = $name;
		    }
		    $part->{data} = "";
		}
	    }
	    elsif ( $state == 2 and # in MIME data
		    #(length $accum < length($boundary)+4) and
		    $accum =~ m{\G
				(?: ( (?: [^\r] | \r[^\n]
				       | \r\n(?:(?=..)(?!--)|(?=$breg)
				                (?!--\Q$boundary\E)))+  )
				|   (\r\n)(?=\Q--$boundary\E(?:--?)\r?\n|)
				|   (\r?\n)
			       ) }gx ) {
		if ( $1 ) {
		    # saw a `line' of data
		    $part->{data} .= $1;
		}
		elsif ( $3 ) {
		    next LINE;
		} else {
		    #$part->{data} .= $1;
		    if ( my $name = delete $part->{name} ) {
			$param->{$name} = $part->{data};
		    }
		    $state = 0;  # back to between parts
		}
	    } elsif ( $state == 3 
		      and $accum =~ m{\G\s*\Z}s ) {
		# ok
	    } elsif ( !pos $accum ) {
		$accum = substr $accum, $oldpos if $oldpos;
		next CHUNK;
		#die "400 Bad Request (pos = $oldpos, context = ".
		    #substr($accum, $oldpos, 80).")";
	    }
	}
	$accum = substr $accum, (pos($accum)||0);

    }
    ($state == 3) or ($state == 0)
	or die "400 Bad MIME request (state = $state)";

    $self->set_param($param);
}

package PSA::Request::CGI::Upload;

use base qw(Class::Tangram);
our $fields =
    { string => { filename => undef,
		  type     => undef,
		},
      idbif  => { data => undef,
		  headers => undef,
		},
      transient => { mmap => undef,
		   },
    };

use overload
    fallback => 1,
    '""' => \&as_string;

sub as_string {
    my $self = shift;
    $self->get_filename;
}

use IO::File;

sub link {
    my $self = shift;
    my $filename = shift;

    my $handle = IO::File->new();
    $handle->open("+>$filename")
	or die "failed to open $filename for read/write; $!";
    print $handle $self->get_data;

    return $handle;
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

