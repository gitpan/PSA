
package PSA::Acceptor::Dummy;
use strict;
use Carp;
use PSA::Request::CGI;

=head1 NAME

PSA::Acceptor::Dummy - Acceptor for Debug and Interactive purposes

=head1 SYNOPSIS

 my $acceptor = PSA::Acceptor::Dummy->new();

 while (my $request = $acceptor->get_request() ) {

     my $psa = PSA->new(request => $request, ...);

 }

=head1 DESCRIPTION

PSA::Acceptor::Dummy is a PSA::Request object factory.  On invocation,
it prompts for enough information to construct a request object.  This
acceptor deals in HTTP request objects.

The environment is permitted to contain pre-loaded information, which
is presented as the defaults.  If the environment variable SUCK_DUMMY
is set to a true value, then it is assumed that everything necessary
has been loaded into the environment.

=head1 METHODS

=over

=item PSA::Acceptor::Dummy->new()

Returns a new acceptor object.

=cut

use IO::Handle;
use base qw(PSA::Acceptor);
use Maptastic;

our %defaults = (
		 server_name => "localhost",
		 server_protocol => "http",
		 server_port => "80",
		 gateway_interface => "CGI/1.1",
		 server_software => "NullSoft(tm) STDIN, v2.3",
		 script_name => "/".($0 =~ m{(?:.*/)?(.*)$})[0],
		);

our %hit_defaults = (
		     request_method => "GET",
		     path_info => "",
		     path_translated => `echo -n \`pwd\``,
		     query_string => "",
		     remote_host => "stdin.com",
		     remote_addr => "127.1.2.3",
		     http_cookie => "",
		    #remote_port => "32767",
		    #remote_user => ...
		    #remote_ident => ...
		    # content_type => ...
		    # content_length => ...
		   );

our $fields = {
	       int => { pacified => undef, },
	       string => { (map_each { ($_[0] => { init_default => $_[1] }) }
			    ({ %defaults, %hit_defaults })),
			   base => undef,
			 },
	      };

=item PSA::Acceptor::Dummy->new()

Returns a new acceptor object.  Prompts the user to enter the values
if run from a terminal.

=cut

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);

    $self->init();

}

sub init {
    my $self = shift;

    if ($ENV{SUCK_DUMMY}) {
	$self->set_pacified(1);
    } else {
	local($|) = 1;
	$self->set_max_age(1000);
	print "Please enter CGI headers (ctrl+d to default)\n";
    }

    my $eof;
    for my $k (sort keys %defaults) {
	my $v = $defaults{$k};
	$self->set($k => ($ENV{uc($k)} || $v));

	unless ($eof or $self->pacified or ! -t STDIN ) {
	    print "Value for $k [".$self->get($k)."]? ";
	    my $input = <STDIN>;
	    if (defined($input)) {
		chomp($input);
		$input = "" if ($input eq "\0");
		if ($input) {
		    $self->set($k => $input);
		}
	    } else {
		$eof = 1;
		print "(using defaults)\n";
	    }
	}
    }

    return $self;
}

=item $acceptor->get_request

Returns a PSA::Request derived object, or C<undef> if there are none
available.

This function will probably block.

=cut

sub get_request {
    my $self = shift;

    $self->SUPER::get_request() or return undef;

    my %env = ( map { uc($_) => $self->get($_) } keys %defaults );

    local($|) = 1,
	print "Please enter per-request CGI headers (ctrl+d to skip)\n"
	    unless $self->pacified;

    my $eof;
    for my $k (sort keys %hit_defaults) {
	my $v = $hit_defaults{$k};

	$env{uc($k)} = $ENV{uc($k)} || $v;

	unless ($eof or $self->pacified or ! -t STDIN ) {
	    print "Value for $k [".($env{uc($k)}||"")."]? ";
	    my $input = <STDIN>;
	    if (defined($input)) {
		chomp($input);
		$input = "" if ($input eq "\0");
		if ($input) {
		    $env{uc($k)} = $input;
		    $hit_defaults{$k} = $input;
		}
	    } else {
		$eof = 1;
		print "(using defaults)\n";
	    }
	}
    }

    return PSA::Request::CGI->fetch
	( ($self->{sid_re} ? (sid_re => $self->{sid_re}) : ()),
	  env => \%env );
}

=item $acceptor->output_fd

Returns the filehandle (either an IO::Handle or a ref GLOB) to write
to to respond to this request

=cut

sub output_fd { \*STDERR }

=item $acceptor->stale

Returns true if this acceptor has accepted more than its fair share of
hits, or $0 or any include files have changed

=cut

sub stale {
    my $self = shift;

    my $stale = $self->SUPER::stale;

    if ($self->get_pacified) {
	return $stale;
    } else {
	local($|) = 1;
	print("Another Request "
	      .($stale?"(note: some source files changed)":"")
	      ."[N] ?");
	my $input = <STDIN>;
	chomp($input);
	my $answer = !(defined $input and $input =~ m/^y/i);
	return $answer;
    }
}

our $AUTOLOAD;
sub AUTOLOAD {
    my $self = shift;

    $AUTOLOAD =~ s{.*::}{};

    if (my $rv = $self->{$AUTOLOAD}) {
	return $rv;
    }
}

37;
__END__

=back

=head2 AUTHOR

Sam Vilain, <sv@snowcra.sh>

=cut

