
=head1 NAME

PSA::Test - for writing PSA regression tests

=head1 SYNOPSIS

 use PSA::Test tests => 1;

 SETUP_TEST(my $psa = shift);

 is("this", "that", "This is that");

=head1 DESCRIPTION

PSA::Test is a class for writing short test scripts to run within the
PSA environment.

The idea is, that you write a PSA scriptlet that tests your data model
in some way, and then put such a page in your controller (F<psa-bin/>)
directory somewhere.  This is somewhat incompatible with the style of
placing such tests in the F<t/> folder, so you will probably choose
one style or another.

It is modelled very closely on Schwern's C<Test::More> module.  Pieces
are directly ripped off it.  Largely because I couldn't inherit off
it :-).

=cut

package PSA::Test;

use strict;
use PSA::Test::Builder;

use Carp;
use base qw(Exporter);
use Scalar::Util qw(weaken);

our @EXPORT = qw( ok use_ok require_ok
		  is isnt like unlike is_deeply
		  cmp_ok
		  skip todo todo_skip
		  pass fail
		  eq_array eq_hash eq_set
		  plan
		  can_ok  isa_ok
		  diag
		  SETUP_TEST
		  NAME_TEST
		  BAIL_OUT
		); #$TODO


# The `SchizoSingleton' mechanism.  It's still not completely
# re-entrant, unless you use it in the OO fashion everywhere.
our %o;
sub _obj(\@) {
    my $stackref = shift;

    if (ref $stackref->[0] &&
	UNIVERSAL::isa($stackref->[0], __PACKAGE__)) {
	return shift @{$stackref};
    }

    # find the immediate caller outside of this package
    my $i = 0;
    $i++ while UNIVERSAL::isa(scalar(caller($i))||";->", __PACKAGE__);

    my $caller = caller($i);

    if (exists $o{$caller}) {
	return $o{$caller};
    } else {
	die <<"EOT";
Tried to access the PSA::Test singleton from within package $caller
($i stack frame(s) back), but there was no import from that package.
EOT
    }
}

sub new {
    my $class = shift;
    my $self = { @_ };
    bless $self, $class;
    return $self;
}

sub Test {
    my $self = _obj(@_);
    return $self->{Test};
}

sub import {
    my($class) = shift;
    goto &plan;
}

sub plan {
    my(@plan) = @_;

    my $caller = caller;
    my $self = $o{$caller} ||= __PACKAGE__->new('::' => $caller);

    $self->{Test} ||= PSA::Test::Builder->new();

    $self->Test->output($self->{output} = []);
    $self->Test->failure_output($self->{errors} = []);
    $self->Test->todo_output($self->{todo} = []);

    $self->Test->exported_to($caller);
    $self->Test->plan(@plan);

    my @imports = ();
    foreach my $idx (0..$#plan) {
        if( $plan[$idx] eq 'import' ) {
            @imports = @{$plan[$idx+1]};
            last;
        }
    }

    __PACKAGE__->export_to_level(1, __PACKAGE__, @imports);

}

=head1 TEST FUNCTIONS

=over

=item B<ok>, B<pass>, B<fail>

=item B<is>, B<isnt>, B<cmp_ok>

=item B<like>, B<unlike>

Identical to their C<Test::More> counterparts in function.

=cut

sub ok           { _obj(@_)->Test->ok(@_)     }
sub is ($$;$)    { _obj(@_)->Test->is_eq(@_)  }
sub isnt ($$;$)  { _obj(@_)->Test->isnt_eq(@_)}
sub like ($$;$)  { _obj(@_)->Test->like(@_)   }
sub unlike       { _obj(@_)->Test->unlike(@_) }
sub cmp_ok($$$;$){ _obj(@_)->Test->cmp_ok(@_) }
sub pass (;$)    { _obj(@_)->Test->ok(1, @_)  }
sub fail (;$)    { _obj(@_)->Test->ok(0, @_)  }
sub diag         { _obj(@_)->Test->diag(@_)   }

=item B<can_ok>

Similar to the Test::More version, but implemented in this module.

=cut

sub can_ok($@) {
    my $self = _obj(@_);
    my ($proto, @methods) = @_;
    my $class= ref $proto || $proto;

    unless( @methods ) {
        my $ok = $self->Test->ok( 0, "$class->can(...)" );
        $self->Test->diag('    can_ok() called with no methods');
        return $ok;
    }

    my @nok = ();
    foreach my $method (@methods) {
        my $test = "'$class'->can('$method')";
        local($!, $@);  # don't interfere with caller's $@
                        # eval sometimes resets $!
        eval $test || push @nok, $method;
    }

    my $name = "$class->can(@methods)";

    my $ok = $self->Test->ok( !@nok, $name );

    $self->Test->diag(map "    $class->can('$_') failed\n", @nok);

    return $ok;

}

=item B<isa_ok>

Similar to the Test::More version, but implemented in this module.

=cut

sub isa_ok($@) {
    my $self = _obj(@_);
    my $Test = $self->Test;
    my($object, $class, $obj_name) = @_;

    my $diag;
    $obj_name = 'The object' unless defined $obj_name;
    my $name = "$obj_name isa $class";
    if( !defined $object ) {
        $diag = "$obj_name isn't defined";
    }
    elsif( !ref $object ) {
        $diag = "$obj_name isn't a reference";
    }
    else {
        # We can't use UNIVERSAL::isa because we want to honor isa() overrides
        local($@, $!);  # eval sometimes resets $!
        my $rslt = eval { $object->isa($class) };
        if( $@ ) {
            if( $@ =~ m{^Can't call method "isa" on unblessed reference} #}x
	      ) {
                if( !UNIVERSAL::isa($object, $class) ) {
                    my $ref = ref $object;
                    $diag = "$obj_name isn't a '$class' its a '$ref'";
                }
            } else {
                die <<WHOA;
WHOA! I tried to call ->isa on your object and got some weird error.
This should never happen.  Please contact the author immediately.
Here's the error.
$@
WHOA
            }
        }
        elsif( !$rslt ) {
            my $ref = ref $object;
            $diag = "$obj_name isn't a '$class' its a '$ref'";
        }
    }

    my $ok;
    if( $diag ) {
        $ok = $Test->ok( 0, $name );
        $Test->diag("    $diag\n");
    }
    else {
        $ok = $Test->ok( 1, $name );
    }

    return $ok;

}

=item B<use_ok>

Similar to the Test::More version, but implemented in this module.

Remember to use within a BEGIN { } block for maximum effect.

=cut

sub use_ok($@) {
    my $self = _obj(@_);
    my $Test = $self->Test;
    my($module, @imports) = @_;
    @imports = () unless @imports;

    my $pack = caller;

    local($@,$!);   # eval sometimes interferes with $!
    eval <<USE;
package $pack;
require $module;
$module->import(\@imports);
USE

    my $ok = $Test->is_eq( $@, "", "use $module;" );

    unless( $ok ) {
        chomp $@;
        $Test->diag(<<DIAGNOSTIC);
    Tried to use '$module'.
    Error:  $@
DIAGNOSTIC

    }

    return $ok;

}

=item B<require_ok>

   require_ok($module);

Like use_ok(), except it requires the $module.

=cut

sub require_ok ($) {
    my $self = _obj(@_);
    my $Test = $self->Test;
    my($module) = shift;

    my $pack = caller;

    local($!, $@); # eval sometimes interferes with $!
    eval <<REQUIRE;
package $pack;
require $module;
REQUIRE

    my $ok = $Test->ok( !$@, "require $module;" );

    unless( $ok ) {
        chomp $@;
        $Test->diag(<<DIAGNOSTIC);
    Tried to require '$module'.
    Error:  $@
DIAGNOSTIC

    }

    return $ok;
}

sub skip {
    my $self = _obj(@_);
    my $Test = $self->Test;
    my($why, $how_many) = @_;

    unless( defined $how_many ) {
        # $how_many can only be avoided when no_plan is in use.
        _carp("skip() needs to know \$how_many tests are in the block")
	    unless $Test::Builder::No_Plan;
        $how_many = 1;
    }

    for( 1..$how_many ) {
        $Test->skip($why);
    }

    local $^W = 0;
    last SKIP;
}




=item SETUP_TEST($psa)

Sets up the test environment - sets up where the `local' PSA object
is.

=cut

sub SETUP_TEST($) {
    my $self = $o{caller()};

    my $psa = $self->{psa} = shift;
    $self->{filename} = $psa->filename(caller());

    $self->Test->output($self->{output} = []);
    $self->Test->failure_output($self->{errors} = []);
    $self->Test->todo_output($self->{todo} = []);

    for my $param (qw(loud terse verbose quiet image)) {
	my $v = $psa->request->param($param);
	if (defined $v) {
	    $self->{$param} = $v;
	}
    }

    $self->setup_response;
}

sub NAME_TEST($) {
    my $self = $o{caller()};
    $self->{title} = shift;
}

sub BAIL_OUT(;$) {
    my $self = $o{caller()};
    my $reason = (shift) || "oh, the insanity!";

    $self->fail("BAILED OUT: ".$reason);

    (my $label = caller()) =~ s{.*::}{};

    print STDERR "PSA::Test: last $label (called is ".caller().")\n";
    eval "last $label";
}

sub setup_response {
    my $self = _obj(@_);

    # tv = template vars
    $self->{tv} ||= { filename => $self->{filename} };

    # Setup a template response
    $self->{psa}->response->set_template
	([
	  Template => "t/test_results",
	  $self->{tv},
	 ]);

    # clean-up some references so that there is a remote chance of
    # memory being freed
    $self->{psa}->response->set_pre_hooks
	([ sub {
	    $self->complete_response();
	    $self->lynx() } ]);

    $self->{tv}->{response} = $self->{psa}->response;
    $self->{tv}->{hooks} = $self->{psa}->response->pre_hooks;
}

sub lynx {
    my $self = _obj(@_);

    if ($self->Test) {
	$self->Test->lynx();
    }
    delete $self->{$_} foreach ( grep { ! m/^(::|Test)$/ } keys %$self );
    return $self;
}

sub complete_response {
    my $self = _obj(@_);

    # ... insert test results into template variables ...
    $self->{tv}->{summary} = [ $self->Test->summary ];
    $self->{tv}->{details} = [ $self->Test->details ];
    $self->{tv}->{output} = $self->{output};
    $self->{tv}->{errors} = $self->{errors};
    $self->{tv}->{todo} = $self->{todo};
    $self->{tv}->{title} = $self->{title};
    $self->{tv}->{filename} = $self->{filename} || "";
    ($self->{tv}->{basename} = $self->{filename}) =~ s{.*/}{};

}

=item $o->template

(internal) Returns the template that is adequate for displaying this
set of test results, based on the configured settings of B<verbose>,
B<image>, etc.

=cut

sub template {
    my $o = shift;
    return ($o->{image} ? "t/res_image"
	    : ( $o->{verbose} ? "t/test_results" : "t/plain_results" ) );

}

1;

__END__

=back

=head1 SEE ALSO

L<PSA>, L<PSA::Cache::Entry>

=cut

