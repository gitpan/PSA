package PSA::SandCastle;

=head1 NAME

PSA::SandCastle - the result of a program execution

=head1 SYNOPSIS

t.b.c.

=head1 DESCRIPTION

Used to be useful with page types like L<PSA::Cache::Entry::ePerl> and
L<PSA::Cache::Entry::PSA>, that printed their output to STDOUT.
However, given the flaky nature of the debugger etc with this sort of
arrangement, this approach was deprecated.

=cut

use strict;
use Carp;

use Class::Tangram;
use vars qw($schema @ISA);
@ISA = qw(Class::Tangram);

$schema =
    {
     fields =>
     {
      perl_dump => {

		    # the output of the program
		    stdout => undef,
		    stderr => undef,

		    # $@, warnings from program
		    errors => undef,

		    # return values - scalar or array ref
		    return => undef,

		    # might also store args passed, etc. if used for
		    # prebuilding pages
		    where => undef,
		   },
     }
    };

sub is_success($) {
    my ($self) = (@_);

    if ($self->{errors} or $self->{stderr}) {
	return undef;
    } else {
	return 1;
    }
}

sub isnt_success { !$_[0]->is_success() }

# for capturing STDOUT and STDERR
sub capture_stdout_and_stderr($) {
    my $self = shift;

    #   capture STDOUT and STDERR
    $self->{so} = tie(*STDOUT, __PACKAGE__, \$self->{stdout})
	or croak "failed to tie STDOUT";
    $self->{se} = tie(*STDERR, __PACKAGE__, \$self->{stderr})
	or croak "failed to tie STDERR";

    # make sure STDOUT is the selected filehandle
    select STDOUT;

    1;
}

sub capture_stderr($) {
    my $self = shift;

    #   capture STDERR
    $self->{se} = tie(*STDERR, __PACKAGE__, \$self->{stderr})
	or croak "failed to tie STDERR";

    1;
}


# release it
sub release_stdout_and_stderr($) {
    my ($self) = shift;

    delete $self->{so};
    delete $self->{se};
    untie(*STDOUT);
    untie(*STDERR);
}

sub warning($$) {
    my ($self, $warning) = (@_);

    $self->{errors} .= $warning;
    return;
}

sub TIEHANDLE {
    my ($class, $c) = @_;
    return bless({ where => $c },$class);
}

sub PRINT {
    my ($self) = shift;
    # oof, how little I knew when I wrote this.
    ${$self->{where}} .= join('', map { defined $_?$_:""} @_);
    return;
}

sub PRINTF {
    my ($self) = shift;
    my ($fmt) = shift;
    ${$self->{where}} .= sprintf($fmt, @_)
	if (@_);
    return;
}

sub is_null {
    my ($self) = (@_);

    if ($self->{stdout}) {
	return undef;
    } else {
	return 1;
    }
}

"Save the Whales!";
