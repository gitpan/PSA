
package PSA::Response::HTTP;

=head1 NAME

PSA::Response::HTTP - a HTTP response object

=head1 SYNOPSIS

 my $response = PSA::Response::HTTP->new();

 # redirects
 $response->make_redirect("http://where/");

 # response built from templates, template toolkit in this case
 $response->set_template([Template => "filename", $vars ])

 # manually set the body of the document
 $response->set_data($document_body);

 # SENDFILE
 $response->set_file($filename);

 # set a cookie
 $response->set_cookie(new CGI::Cookie(...));

 # issue the response - select the filehandle you want to write to
 # first
 $response->issue();

 # allow response to contain "Template" templates
 $response->issue(Template => sub { $template->process(@_) });

=head1 DESCRIPTION



=cut

use constant DEBUG => 0;

use strict;
BEGIN { eval "use warnings;" }
use Carp;

use vars qw(@ISA @EXPORT_OK $schema);
use Exporter;
use Class::Tangram;
@ISA = qw(Exporter Class::Tangram PSA::Response);
@EXPORT_OK = qw($schema);

use Fcntl;
use CGI::Util qw(expires);

$schema =
    {
     fields => {

		# store header values, IN HTTP RFC FORM, or CGI.pm FORM!
		# store cookie
		idbif => [ qw( header data cookie tag sendfile) ],

		string => { template => undef,
			    file => { col => "sentfile" },
			  },

		transient => { pre_hooks => { init_default => [ ] } },

		# set if the document is to be a non-terminal part of
		# a server push response.
		int => [ qw(nonfinal) ],
	       }
    };

Class::Tangram::import_schema(__PACKAGE__);

=head2 new

Creates a new PSA::Response::HTTP object

=cut

sub new($;@) {
    my ($class, %params) = (@_);

    my $self;
    if (!defined $self) {
	$self = $class->SUPER::new(%params);
	$self->{header} ||= { Pragma  => 'no-cache',
			      Expires => "-10m",
			      'Content-Type' => "text/html",
			      #-server  => "your mum (ports always open)",
			    };
    }

    bless $self, $class;
    return $self;
}

=head2 $response->set_static

Sets some headers that permit caching of the file

=cut

sub set_static {
    my $self = shift;

    delete $self->{header}->{Pragma};
    $self->{header}->{Expires} = "+4h";
    if ( $self->{file} ) {
	$self->set_header
	    (-last_modified => expires((stat $self->{file})[10]));
    }

}

#  _cgipm_headerify - converts passed options from CGI.pm format to
#  standard HTTP format
sub _uncgipm_headerify {

    my $i = 0;
    while ($i < $#_) {
	if ($_[$i] =~ s/^-//) {
	    $_[$i] =~ tr/_/-/;
	    $_[$i] =~ s{\b(\w)(\w*)}{uc($1).lc($2)}eg;
	    $_[$i] =~ s{^(Type|Length)$}{Content-$1};
	}
	$i += 2;
    }

    @_;
}

=head2 $response->cgiheader

returns a valid CGI header for this page

=cut

# from RFC 2616, what a lot of junk
our %status =
    ( 100 => "Continue",
      101 => "Switching Protocols",
      200 => "OK",
      201 => "Created",
      202 => "Accepted",
      203 => "Non-Authoritative Information",
      204 => "No Content",
      205 => "Reset Content",
      206 => "Partial Content",
      300 => "Multiple Choices",
      301 => "Moved Permanently",
      302 => "Found",
      303 => "See Other",
      304 => "Not Modified",
      305 => "Use Proxy",
      307 => "Temporary Redirect",
      400 => "Bad Request",
      401 => "Unauthorized",
      402 => "Payment Required",
      403 => "Forbidden",
      404 => "Not Found",
      405 => "Method Not Allowed",
      406 => "Not Acceptable",
      407 => "Proxy Authentication Required",
      408 => "Request Timeout",
      409 => "Conflict",
      410 => "Gone",
      411 => "Length Required",
      412 => "Precondition Failed",
      413 => "Request Entity Too Large",
      414 => "Request-URI Too Long",
      415 => "Unsupported Media Type",
      416 => "Requested Range Not Satisfiable",
      417 => "Expectation Failed",
      500 => "Internal Server Error",
      501 => "Not Implemented",
      502 => "Bad Gateway",
      503 => "Service Unavailable",
      504 => "Gateway Timeout",
      505 => "HTTP Version Not Supported",
    );

#our $no_content = qr/(?:1..|30[1-7])/;

our $CRLF = "\015\012";  # EBCDIC be damned!  :)

sub httpheader {
    my $self = shift;
    my $status = $self->{header}->{Status} || 200;

    my @header;
    if ( exists $status{$status} ) {
	push @header, "HTTP/1.1 $status $status{$status}";
    } else {
	push @header, "HTTP/1.1 $status";
    }

    while ( my ($header, $value) = each %{ $self->{header} } ) {
	# hacks for various headers
	if ( $header eq "Expires" and $value =~ m/^\s*[\-+]/ ) {
	    $value = expires($value, "http");
	}
	next if $header eq "Status";
	#next if ($header eq "Content-Type" and $status =~ m/^$no_content/);
	push @header, "$header: $value";
    }

    # cookie
    if ( $self->{cookie} ) {
	push @header, "Set-Cookie: "
	    .(UNIVERSAL::can($self->{cookie}, "as_string")
	      ? $self->{cookie}->as_string : $self->{cookie} );
    }

    push @header, "Date: ".expires(time, "http");

    print STDERR __PACKAGE__ . ": >-\n",join("\n",@header)."\n...\n"
	if DEBUG;

    return join "\r\n", @header, "", "";
}

sub cgiheader($) {
    my ($self) = (@_);
    $self->isa("PSA::Response::HTTP") or croak "type mismatch";

    if ( $self->nonfinal or $self->{_sent_header}) {

	$self->{_type} = delete $self->{header}{'Content-Type'}
	    || "text/html";
	$self->{_length} = delete $self->{header}{'Content-Length'};

	my $header = "";
	if ( ! $self->{_sent_header} ) {
	    local($self->{header}{'Content-Type'}) =
		"multipart/x-mixed-replace;boundary=OOK";
	    $header = $self->httpheader;
	    $self->{_sent_header} = 1;
	    delete $self->{cookie};
	}
	$header .= ("$CRLF--OOK$CRLF"
		    ."Content-Type: $self->{_type}$CRLF"
		    .($self->{_length}
		      ? "Content-Length: $self->{_length}$CRLF"
		      : "")
		    .$CRLF);

	return $header;

    } else {
	return $self->httpheader;
    }
}

=head2 $response->make_redirect($uri)

Turns this response into a redirect

=cut

sub make_redirect {
    my ($self, $uri) = @_;

    $self->{header}{Location} = $uri;

    $uri = CGI::Util::simple_escape($uri);
    $self->{data} = <<"HTML";
<html>
  <head>
    <meta http-equiv="refresh" content="0; $uri" />
  </head>
  <body>
    <a href='$uri'>redirect ye</a>
  </body>
</html>
HTML

    $self->{header}{Status} = 302;
    delete $self->{template};
    delete $self->{file};
}

=head2 $response->trigger()

=cut

sub trigger {
    my $self = shift;
    foreach my $closure (@{$self->pre_hooks}) {
	&{$closure}($self);
    }
}

=head2 $response->issue(Toolkit => sub { ... })

Issues this HTTP response - if the response was made a template
response (with set_template), then it calls the appropriate sub with
the args as passed to set_template.

If the response is a file, as set by $response->set_file(), then that
file is printed out.

=cut

sub issue {
    my $self = shift;
    $self->isa("PSA::Response::HTTP") or croak "type mismatch";

    $self->trigger();

    if ( $self->{template} ) {
	my %methods = (@_);
	(my $toolkit, @_) = @{$self->{template}};

	# must be provided with the method
	die("Template response type set to `$toolkit', but "
	    ."issue() was not told how to deal with that toolkit "
	    ."type") unless $methods{$toolkit};

	# print the header
	my $header = $self->cgiheader;
	print $header;

	# call the specified method
	return $methods{$toolkit}->(@_);

    } elsif ($self->{file}) {

	my $fn = $self->{file};
	my $size = -s $self->{file};

	if ( $self->sendfile and
	     !$self->{_sent_header} and
	     !$self->nonfinal ) {

	    if ($fn =~ s{^(/.*/([^/]*))/}{}) {

		if (!lstat("inc/$2")) {
		    (-d "inc") || mkdir("inc")
			or die "Failed to create inc; $!";
		    symlink($1, "inc/$2")
			or die "Failed to create inc/$2; $!";
		}

		$fn = "inc/$2/$fn";
	    } else {
		$fn =~ s{^(\./)+}{};
	    }

	    $self->{header}->{'Content-Length'} = $size;
	    delete $self->{header}->{'Content-Type'};
	    $self->{header}->{Location} = "/inc/$fn";

	    #print "Location: /X/$fn\n\n";
	    print $self->cgiheader;
	} else {

	    sysopen (FILE, $self->{file}, O_RDONLY)
		or die "cannot open $self->{file} for reading; $!";

	    print $self->cgiheader;

	    # read blocks in chunks of preferred filesystem IO speed
	    my $blocksize = ((stat FILE)[11]) || 4096;
	    my $buffer;
	    # FIXME - no error check from the sysread - will return
	    # empty documents on IO error
	    while (my $bytesread = sysread FILE, $buffer, $blocksize) {
		print $buffer;
	    }
	    close FILE;
	}

    } elsif ( $self->{data} ||= "Nothing to say, sorry" ) {
	# default type for data is text/html
	my $size = length $self->{data};

	# set the content length so that browsers show progress
	# bars (it's the little things...) :-)
	$self->{header}->{'Content-Length'} = $size;

	my $header = $self->cgiheader;
	#print STDERR "OUTPUT: >-\n$header$self->{data}\n...\n";
	print $header, $self->{data};
    }
}

=head2 set_file($value)

Not only does it set the value of $value, but has a guess at the mime
type too.

=cut

use vars qw($magic_loc $mm);
use FileHandle;

BEGIN {
    # Detect MIME magic settings
    eval 'use File::MMagic';
    if ( !$@ ) {
	($magic_loc) = map { ( -f $_ ? $_ : () ) }
	    qw( etc/magic /usr/share/etc/magic /etc/magic );

	# Or fall back to defaults
	$mm = File::MMagic::new($magic_loc or ());
    }
}

# guh.
my %even_more_magic_types =
    ( js => "text/javascript",
      css => "text/css",
    );

sub set_file {
    my $self = shift;
    my $value = shift;

    my $type = shift;
    $type or do {
	if ( $value =~ /\.(\w+)$/ and exists $even_more_magic_types{$1} ) {
	    $type = $even_more_magic_types{$1}
	} elsif ( $mm ) {
	    $type = $mm->checktype_filename($value);
	    # workaround "dumbass default" bug in Apache::MMagic
	    $type = "text/plain" if $type =~ m{^x-system/};
	} else {
	    warn "No idea what type stream response is; assuming text/plain"
	}
    };

    $self->set_header(-type => $type);
    $self->set_header(-length => -s $value);
    $self->{file} = $value;

}

=head2 set_data_magic($data)

Sets the response to the specified data format, then auto-guesses the
file contents and sets the MIME type accordingly

=cut

sub set_data_magic {
    my $self = shift;
    my $data = shift;

    $mm = File::MMagic::new($magic_loc or ());

    $self->set_header(-type => $mm->checktype_contents($data))
	|| die "Cannot guess MIME type of (internal data)";

    $self->set_data($data);

}

=head2 set_header($name => $value)

Sets an HTTP header for this response, in either CGI.pm or HTTP form

=cut

sub set_header($$$) {
    my ($self, $name, $value) = (@_);

    _uncgipm_headerify($name, $value);
    $self->{header}->{$name} = $value;
}

=head2 is_null

Returns 1 if the response has no data, template or file.

=cut

sub is_null($) {
    my $self = shift;

    if ($self->{data} or $self->{template} or $self->{file}
	or $self->{header}->{Location}) {
	return undef;
    } else {
	return 1;
    }
}

sub is_redirect {
    my $self = shift;

    return $self->{header}->{Location};
}

"cthulhu ph'tang!";
