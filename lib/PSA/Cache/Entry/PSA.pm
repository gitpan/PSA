package PSA::Cache::Entry::PSA;

use strict;
use Carp;

use vars qw(@ISA);
use Class::Tangram;
use PSA::Cache::Entry;
@ISA = qw(Class::Tangram PSA::Cache::Entry);

#use Parse::ePerl;

=head1 NAME

PSA::Cache::Entry::PSA

=head1 SYNOPSIS

 <?psa my ($psa, @args) = (@_) ?>
 <?xml version="1.0" encoding="UTF-8"?>
 <!DOCTYPE html 
      PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
     "DTD/xhtml1-strict.dtd">
 <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en"
       lang="en">
   <head>
     <!-- Insert a one-liner, HTML escaped.  Idea stolen
          from PSP -->
     <title>[+ $variable +]</title>
   </head>
   <body>
     <p>
       <!-- Enclose some arbitary Perl.  Core of ePerl -->
       <?psa print("Ring, ring.");
         print $variable ?>

       <form action="foo.psa">
         <input type="hidden" name="sid" value="[- $sid -]">
         <?psa
            # alternative to the above
            print CGI::escape(qq{<input type="hidden"
                                 name="sid" value="$sid">})
            # call a sub-page, with the given argument
            $psa->include("widget.psa", $user);

            # pages are turned into subs, so return a closure to it.
            # $widget->() will be exactly the same as above
            my $widget = $psa->closure("widget.psa", $user); ?>

            # for example, call a template that takes a
            # widget as a parameter
            $psa->include("pageelement.psa", $widget);

            # access the CGI object
            my $p = $psa->CGI->param("parameter");

            # set a cookie
            $psa->response->set_cookie($cookie);
            ?>

         <!-- Internationalisation -->

         <?psa
           Lexicon->lang = "fr";  # optional, set language
          ?>

         <!-- converted to _("_tag") -->
         [* _tag *]

         <!-- list - call maketext -->
         [* $variable, $foo, $bar *]

         <!-- Lexicon - constant first argument -->
         [* 'Your search matched [quant,_1,document].', $hit_count *]

       </form>
     </p>
   </body>
 </html>

=head1 DESCRIPTION

A derived class of PSA::Cache::Entry.  An object of this type
merely runs a different sort of preprocessing when it is compiled.

=cut

# it is not expected that these will be stored in a database, due to
# a lack of stability of the B::Bytecode backend.
use vars qw($schema);
$schema =
    {
     table => "compiled_pages",
     bases => [ qw(PSA::Cache::Entry) ],
     fields => { },
    };

=head1 METHODS

=head2 preprocess

Force a compilation of the source file, returns true or croaks with
compilation error/warning/file not found/etc

=cut

use vars qw($num);
$num = 0;

sub preprocess {
    my $self = shift;
    $self->isa("PSA::Cache::Entry::PSA")
	or confess "type mismatch";

    #   translate the script from bristled ePerl format to plain Perl
    #   format - more to come here
    my $init;

    delete $self->{preprocessed};

    # line counts
    my $lc = 1;
    my $olc = 0;

    my $uses_lexicon;

    # FIXME - unclosed openings
    while ( scalar ($self->{source} =~ m/\G(
				       <\?psa(_init)?\b(.*?)\?>
				   |   \[ (?:   # this is getting
				              \+(.*?)\+ \]  #rid
				          |   - (.*?) - \]  #ic
				          |   \#(.*?)\# \]  #u
				          |   \*(.*?)\* \]  #lus
				          |   \=(.*?)\= \]
				          |   \/(.*?)\/ \]
				          )
				   |   (.+?)(?=<\?psa(?:_init)?|\[[-+*=\#]|$)
				   )
				 /sxg)) {

	my ($all, $is_init, $perl_block, $html_esc_block,
	    $cgi_esc_block, $comment_block, $l7d_block, $no_esc_block,
	    $slash_block,
	    $html_block) = ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);

	my @lf = ($all =~ m/(\n)/sg);

	if ( $perl_block ) {
	    if ( $is_init ) {
		$init .= ("\n# line $lc \"$self->{filename}\"\n"
			  .$perl_block."\n;\n");
	    } else {
		if ($lc != $olc) {
		    $self->{preprocessed} .= 
			("\n# line $lc \"$self->{filename}\"\n");
		    $olc = $lc;
		}
		$self->{preprocessed} .= ($perl_block."\n;");
		$olc += @lf + 1;
	    }
	} else {
	    if ($lc != $olc) {
		$self->{preprocessed} .= 
		    ("\n# line $lc \"$self->{filename}\"\n");
		$olc = $lc;
	    }
	    if ( $html_esc_block ) {
		$self->{preprocessed} .= ("print CGI::escapeHTML("
					  .$html_esc_block. ");");
		$olc += @lf;
	    } elsif ( $cgi_esc_block ) {
		$self->{preprocessed} .= ("print CGI::escape("
					  .$cgi_esc_block. ");");
		$olc += @lf;
	    } elsif ( $l7d_block ) {
		# FIXME - escaping isn't very simple
		$self->{preprocessed} .= ("print \$lexicon->lookup("
					  .$l7d_block.");");
		$olc += @lf;
		$uses_lexicon = 1;
	    } elsif ( $no_esc_block ) {
		$self->{preprocessed} .= ("print ($no_esc_block);");
		$olc += @lf;
	    } elsif ( $comment_block ) {
		# ignore
	    } else {
		$html_block =~ s/'/\\'/g;
		$self->{preprocessed} .= ("print '$html_block';");
		$olc += @lf;
	    }
	}

	$lc += @lf;
    }

    (my $A = $self->{filename}) =~ s/'/\\'/g;
    $self->{preprocessed} = "package PSA::Root::PSA$num;
" . ($init||"").";
# line 168 \"$INC{'PSA/Cache/Entry/PSA.pm'}\"
use CGI qw(escape escapeHTML);
sub { \n" .
    ($uses_lexicon? "my \$lexicon;
if ( UNIVERSAL::isa(\$_[0], 'Lexicon') ) {
    \$lexicon = shift;
} else {
    #\$lexicon = Lexicon->Default;
}
":"")
.$self->{preprocessed}."; return}";

    $self->set_pkg("PSA::Root::PSA$num");

    ++$num;
    delete $self->{source};
    return 1;
}

=head2 run (@args)

Runs the entry, but croaks if not called with the first argument a PSA
object.

=cut

sub run {
    #my ($self) = (@_);
    #confess ("First argument to PSA::Cache::Entry::PSA::run not a "
	     #."PSA object but a ".(ref shift))
	#unless $_[1]->isa("PSA");

    #$self->SUPER::run(@_);
    #goto $_[0]->SUPER::run;
    goto &PSA::Cache::Entry::run;
}

1;
