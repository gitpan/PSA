
my $psa = shift;

use Template;

my ($template, $vars) = (@_);

our $template_obj ||= Template->new
    ({
      INCLUDE_PATH => 'templates',
      INTERPOLATE  => 1,
      POST_CHOMP   => 1,
      EVAL_PERL    => 1,  # evaluate Perl code blocks
                          # because TT's syntax bites
      OUTPUT       => $psa->acceptor->output_fd,
      CACHE_SIZE => 20,
      COMPILE_EXT => ".TT",
      COMPILE_DIR => "var/cache",
      # PLUGINS => { foo => Package },
     });


# define two standard template variables - SID, and "uri".
$vars->{SID} = $psa->sid;
$vars->{uri} = sub { $psa->request->uri(@_) };

$template_obj->process($template, $vars)
    or print "Error: ".$template_obj->error;
