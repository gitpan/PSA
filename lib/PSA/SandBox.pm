
package PSA::SandBox;

=head1 NAME

PSA::SandBox - Run a piece of code in a SandBox

=head1 SYNOPSIS

use PSA::SandBox;
my $sandbox = PSA::SandBox->new( safe => $safe );
my $result = $sandbox->do(sub { });

=head1 DESCRIPTION

PSA::SandBox runs a piece of code in a "Sand Box" - an execution
environment that captures all of the code's output.  The result is a
PSA::SandCastle object.  See L<PSA::SandCastle>.

Note that this is not a "prison", so no use of "Safe" is automatic; if
you supply a safe to the constructor it will be used, but if you don't
there's nothing to stop the piece of code running amok.

This was primarily intended for ePerl style PSA pages, that print
their output to STDOUT (or, more accurately, the selected filehandle).

Note: the Safe feature is not implemented yet.

=cut

package PSA::SandBox;

use Class::Tangram;
use vars qw($schema @ISA);
@ISA=qw(Class::Tangram);

$schema =
    {
     fields => {
		# note: this will be restricted to 255 characters
		string => [ qw(cwd) ],
		ref => { result => {class => "PSA::SandCastle" } },
		perl_dump => [ qw(safe env) ],
	       }
    };

=head1 METHODS

=head2 do(\&code, @args)

=cut

use Cwd qw(fastcwd);
use Carp;
use PSA::SandCastle;

# set if you're in the debugger and don't like segfaults, but don't
# mind the code not producing any results :)
use vars qw($NOTIE);

sub do {
    my $self = shift;
    my $code = shift;
    (my @args, @_) = (@_);
    ref $code eq "CODE" or croak "type mismatch to PSA::SandBox";

    my ($ocwd, %OENV);

    # change to the correct directory
    if ($self->{cwd}) {
	$ocwd = fastcwd();
	chdir($self->{cwd});
    }

    # prepare the result variable
    my $result = PSA::SandCastle->new();
    $self->{result} = $result;

    {
	local %ENV = %{$self->{env}} if $self->{env};
	# Not sure if this is actually needed any more...
	local $SIG{'__WARN__'} = sub { $result->warning(shift); };
	local $SIG{'__DIE__'} = sub { $result->warning(shift);
				      confess "killed by exception" };

	$result->capture_stdout_and_stderr unless ($NOTIE or $ENV{"NOTIE"});

	eval {
	    # preserve array/scalar context
	    $result->set_return ( wantarray ?
				  [ $code->(@args) ]
				  : scalar $code->(@args) );
	};
	$result->warning($@) if $@;

	$result->release_stdout_and_stderr unless ($NOTIE or $ENV{"NOTIE"});
    }
    ($self->{cwd}) && chdir($ocwd);

    $result;
}
