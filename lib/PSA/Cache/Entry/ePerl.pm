#
#  PSA::Cache::ePerlEntry - an entry in a PSA::Cache that uses
#                               an ePerl file as the backend
#
#  Many parts taken from Parse::ePerl
#

# This code might not work anymore - I haven't tested it recently.  I
# decided that the advantage of having a preprocessor as an XS module
# (speed) is not worth the price (inflexibility).  Included for
# interest's sake.
#

package PSA::Cache::Entry::ePerl;

use strict;
use Carp;

use Class::Tangram;
use PSA::Cache::Entry;

use Parse::ePerl;

# it is not expected that these will be stored in a database, due to
# a lack of stability of the B::Bytecode backend.
use vars qw($schema @ISA);
@ISA = qw(Class::Tangram PSA::Cache::Entry);
$schema =
    {
     table => "compiled_pages",
     bases => [ qw(PSA::Cache::Entry) ],

     # what more do we need to know?  It's the object type that counts
     fields => { },
    };

#---------------------------------------------------------------------
#  compile(\$script) - force a compilation of the source file, returns
#  true or croaks with compilation error/warning/file not found/etc
#---------------------------------------------------------------------
sub compile($$) {
    my ($self, $script) = (@_);
    $self->isa("PSA::Cache::ePerlEntry") or croak "type mismatch";

    #   run the preprocessor over the script
    Parse::ePerl::Preprocess ({ Script => $$script,
				Result => \$script,
			        Error => \$self->{error} })
	    or croak ("Error during preprocessing of "
		      .$self->{filename}."; $self->{error}");

    #   translate the script from bristled ePerl format to plain Perl
    #   format
    Parse::ePerl::Translate ({ Script          => $script,
			       BeginDelimiter  => '<?',
			       EndDelimiter    => '?>',
			       Result          => \$script,
			       Error           => \$self->{error} })
	    or croak ("Error during translation of "
		      .$self->{filename}." from ePerl to perl; "
		      .$self->{error});

    # compile it.
    my $class = ref $self;
    return $self->SUPER::compile(\$script);
}

17;
