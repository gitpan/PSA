
use constant DEBUG => 0;

my $psa = shift;

use Template;

my ($template, $vars, $no_header) = (@_);

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
      TAG_STYLE => "asp",
      PROCESS => "layout.tt",
      TRIM => 1,
      # PLUGINS => { foo => Package },
     });


# define two standard template variables - SID, and "uri".
$vars->{SID} = $psa->sid;
$vars->{uri} = sub { $psa->request->uri(@_) };
$vars->{oid} = sub { $psa->storage->export_object(@_) };
$vars->{template} = $template;
$vars->{is_ie} = $psa->request->env->{HTTP_USER_AGENT} =~ m/MSIE/;

print STDERR "Processing $template with :" .Data::Dumper::Dumper($vars)
    if DEBUG and $template !~ m{^err/};
local($vars->{psa}) = $psa;

print $psa->response->cgiheader unless $no_header;
$template_obj->process($template, $vars)
    or print "Error: ".$template_obj->error;
