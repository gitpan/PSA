
package Capture;

use base qw(Class::Tangram);
use vars qw($schema);

$schema = { fields => { perl_dump => [ qw(stdout)]  } };

sub capture_print {
    my $self = shift;
    #open STDCAPTURE, ">/dev/null" or die $!;
    $self->{so} = tie(*STDOUT, 'Capture', \$self->{stdout})
	or die "failed to tie STDOUT; $!";

    #select STDCAPTURE;
}

sub release_stdout {
    my $self = shift;
    delete $self->{so};
    untie(*STDOUT);
}

sub TIEHANDLE {
    my $class = shift;
    my $ref = shift;
    return bless({ stdout => $ref }, $class);
}

sub PRINT {
    my $self = shift;
    ${${$self->{stdout}}} .= join('', map { defined $_?$_:""} @_); 
}

sub PRINTF {
    my ($self) = shift;
    my ($fmt) = shift;
    ${${$self->{stdout}}} .= sprintf($fmt, @_)
	if (@_);
}


sub glob {
    return \*STDOUT;
}

