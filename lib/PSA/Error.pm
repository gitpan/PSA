#  -*- perl -*-

package PSA::Error;

=head1 NAME

PSA::Error - Handy wrapper for $your_favourite_log_module

=head1 SYNOPSIS

  # use automatic, unless configured otherwise
  my $psa = shift;

  # debug/verbose messages
  whisper "About to do something small, var1 = $var1";
  mutter "Authenticating request";

  # These are all logged, `business as usual' conditions
  reject "Request invalid (not well formed)"
      unless $psa->request->well_formed;

  say "Processing Request";

  # Henceforth the error conditions - first soft errors
  my $xmlns = $psa->request->xmlns;
  if ($xmlns) {
      if ($xmlns ne $proper_xmlns) {
          desist "Incorrect XMLNS on request";
      } else {
          whisper "XMLNS correct";
      }
  } else {
      moan "Missing XMLNS, assuming default";
  }

  # now, bad errors
  if (!$psa->storage->ping) {
      complain "Storage went away!";
      barf "Storage not accessible!"
        unless $psa->storage->reconnect;
  }

  # worse errors - stop a session
  $inventoryItem->hotel or choke "Orphaned Inventory Item!";

  # worse errors - stop a section / site / account
  $hotel->hotelInfo
      or melt "Hotel missing hotelInfo object!";

  # serious errors - stop everything
  $receipt->payer
      or explode "Making mistakes with money!";

=head1 DESCRIPTION

PSA::Error is a class that encapsulates errors from PSA pages, and
provides an easy interface for raising them.  It doesn't actually stop
anything, that is up to the event subscribers.

The logic behind all the different keywords, is that this is ugly:

  $inventoryItem->hotel or do {
     my $logger = Log::Log4perl->new("location" => "somewhere");
     $logger->log(FATAL, "some message");
  };

What a load of bollocks.  Let's just use the resplendant variety of
non-colourful expletives provided by the King's English, and get on
with coding.

This module is used by default for all PSA pages, so they can all
B<moan>, B<shout> and B<complain> to their heart's content.  Nice.

=cut

use base qw(Exporter);
no strict;  # use strict is for wimps anyway
use Carp;

BEGIN {

    %SEV = map { $_ => $c++ }
    @SEV = (debug, info, notice, warning, err, crit, alert, emerg);

    %FUNCS =
	(
	 explode => [ "FUCK!! ",    $SEV{emerg},   "die" ],
	 melt    => [ "SHIT! ",     $SEV{alert},   "die" ],
	 choke   => [ "DAMN! ",     $SEV{crit},    "die" ],
	 barf    => [ "ARSE! ",     $SEV{err},     "die" ],
	 desist  => [ "BOLLOCKS! ", $SEV{warning}, "die" ],
	 reject  => [ "Rejected: ", $SEV{notice},  "die" ],
	 stop    => [ "Stopped: ",  $SEV{info},    "die" ],
	 drop    => [ "Dropped: ",  $SEV{debug},   "die" ],

	 scream  => [ "FUCKING HELL! ", $SEV{emerg}      ],
	 yell    => [ "HOLY SHIT! ",    $SEV{alert}      ],
	 shout   => [ "DAMN IT! ",      $SEV{crit}       ],
	 complain=> [ "WARNING: ",      $SEV{err}        ],
	 moan    => [ "warning: ",      $SEV{warning}    ],
	 say     => [ "",               $SEV{notice}     ],
	 mutter  => [ "info: ",         $SEV{info}       ],
	 whisper => [ "o==*- ",         $SEV{debug}      ],
	);

    while (my ($func, $info) = each %FUNCS) {
	*{$func} = sub {
	    # shortcut all those heavy log modules :)
	    if ((${ caller()."::DEBUG" }||0) >= 2 - $info->[1]) {
		my $message = shift;
		if (ref $message) {
		    ref $message eq "CODE"
			or croak "message $message bad ref";
		    $message = $message->();
		}
		goto &log(level => $info->[1],
			  message => ($info->[0].(shift)),
			  
	    }
        };
    }

    our @EXPORT =
	qw(explode melt choke barf desist reject abort drop
	   scream yell shout complain moan say mutter whisper
	  );

}

use strict;
use base qw(PSA::Audit);
use Set::Object qw(blessed is_string);
use warnings;
use Carp qw(croak cluck);

BEGIN {
    use base qw(Exporter);

    our @EXPORT = qw(RPCError);
    our @EXPORT_OK = qw(RPCError);
}

our $schema = {
          'bases' => [
                       'PSA::Audit'
                     ],
          'fields' => {
                        'flat_hash' => {
                                         'details' => {
                                                        'sql' => 'CHAR(64)',
                                                        'type' => 'string'
                                                      }
                                       },
		        'int' => {
				  level => undef,
				 },
                        'string' => {
                                      'message' => {
                                                     'sql' => 'CHAR(64)'
                                                   },
                                      'message_extra' => {
                                                           'sql' => 'TEXT'
                                                         }
                                    }
                      }
        };

our %msgcat
    = (
       'auth_reqd' => ("Authentication is required for this service or"
		      ." action"),
       'int_error' => ("Internal error.  Please contact support for "
		       ."assistance."),
       'ok' => "Transaction completed successfully",
       'ENOSYS' => "Function not implemented",
       'EINVAL' => "Invalid argument",
       'ENOENT' => "No such object",
      );

sub set_err_code {
    my $self = shift;
    my $err_code = shift;

    $self->{err_code} = $err_code;
    if (exists $msgcat{$err_code} and !$self->{message}) {
	$self->set_message($msgcat{$err_code});
    }
}

sub set_message {
    my $self = shift;
    my $message = shift;
    ($self->{message}, $self->{message_extra})
	= ( (substr $message, 0, 64),
	    (length($message) > 64 ? (substr $message, 64) : "") );
}

sub get_message {
    my $self = shift;
    return undef unless defined $self->{message};
    return $self->{message}.$self->{message_extra};
}

sub RPCError {

    my $error = __PACKAGE__->new();
    my $psa;

    while (@_) {
	my $item = shift;
	if (blessed $item) {
	    # This is a bit of a hack
	    if ($item->isa("PSA")) {
		$psa = $item;
	    } else {
		die "What do you expect me to do with a ".ref($item)
		    ."?";
	    }
	}
	elsif (is_string($item)) {
	    if ($error->can($item)) {
		$error->set($item => (shift @_));
	    }
	    if (exists $msgcat{$item} or $error->get_message) {
		$error->set_err_code($item);
	    } else {
		$error->set_message($item);
	    }
	}
	else {
	    croak "What do you expect me to do with $item?";
	}
    }

    $error->set_err_code("int_error") unless $error->err_code;

    if ($psa) {
	$error->from($psa);
	$psa->run("jsrpc/return.pl", $error);
    }

    return $error;
}

sub JSDUMP_prepare {
    my $self = shift;
    $self->SUPER::JSDUMP_prepare();

    $self->{_class} = ref $self;
    $self->{message} .= delete $self->{message_extra};
}

sub _Error::JSDUMP_restore {
    my $self = shift;

    $self->set_message($self->{message});
    $self->SUPER::JSDUMP_prepare();
}

sub JSDUMP_classname {
    return "_Error";
}

Class::Tangram::import_schema(__PACKAGE__);
1;

__END__

=head2 DESCRIPTION OF ERROR LEVELS

These aliases hide the complexity of using Log::Log4perl, and ensure
that generated pages are easily managable.

All of these methods may take a closure instead of a string (the
closure should return the string to say), so that when verbosity has
been configured to be less, there are as few ignored `Data::Dumper'
runs as possible :-).

Log::Log4perl defines 5 error levels (see L<Log::Log4perl>), however
syslog defines 8 (see L<syslog(3)>); they are mapped as follows:

                             |------ PSA::Page ------|
    Syslog   Log::Log4perl    dies       no die
    debug       DEBUG         drop()     whisper()
    info        INFO          abort()    mutter()
    notice      NOTICE[*]     reject()   say()
    warning     WARN          desist()   moan()
    err         ERROR         barf()     complain()
    crit        fatal         choke()    shout()
    alert       fatal         melt()     yell()
    emerg       fatal         explode()  scream()

These error levels are not expressed by the traditional names, as
these terms are not consistent between implementations of logging
frameworks.

The only difference between the version of the method that calls
die(), and the one that doesn't, is the die.  Both of them are sent to
Log::Log4perl to log.  To the logging system, they are identical.

A summary of each log level, and when you'd normally use them follows.

=over

=item B<Debugging - drop(), whisper()>

These calls are normally only useful when you are debugging the
script.  They are messages for someone who comes along later to debug
the operation of the particular page.

Try not to use this on inner loops, make the messages at least mildly
informative.  No C<whisper("got here")>, please.

Using C<drop> indicates that there is usually going to be no point in
logging the response, and draws its name from similar usage in
firewall rules, as I could think of no other situation where an error
message is something not normally logged.

=item B<Casual Inspection - stop(), mutter()>

This is for the sort of messages that you'd expect B<-v> when given to
a script to issue.  These two conditions are, by definition, not
envisioned to be an error.

=item B<Summary overview - reject(), say()>

This is for the sort of messages you'd expect to be able to find in
the logs for a request on a normal day, or to be able to see printed
to the terminal when running interactively.  Wittering is strongly
discouraged.

B<reject> could be considered closer to B<croak> than B<die>.

=item B<Correctable Errors - desist(), moan()>

These errors mean that something is wrong that B<might> require
attention from the administrator and/or development team.  However, it
is B<not> serious enough to take immediate, automatic action.  This
will certainly be logged in the per-request log file, and might even
raise a touble ticket.

=item B<Uncorrectable Errors - barf(), complain()>

These errors mean that something is wrong that B<probably> requires
attention from the administrator and/or development team.  This B<may>
indicate behaviour that takes a single user's station off-line, with a
message prompting them to call the helpdesk to resolve the situation.

This will probably raise a touble ticket.

=item B<Serious Errors - choke(), shout()>

Something is seriously wrong.  This level of error is B<likely> to
take immediate automatic action, such as de-activating a session and
marking it as requiring debugging.

=item B<Very Serious Errors - melt(), yell()>

As before, but this takes the B<whole Service or wide-scale section of
the application> off-line.  For instance, in a Central Reservation
System for the Hotel Industry :), this might take a whole Hotel, Login
account or Booking Channel offline.  Use with caution.

=item B<"Oh, Shit!" Errors - explode(), scream()>

This indicates an error that is so serious, that B<no transactions may
proceed>.  Not even logins, or reading of information.  The system is
down, wake up the SysAdmin and start escalation procedures.

=back

==head1 SEE ALSO

L<PSA::Config(3pm)>, L<Log::Log4perl(3pm)>, L<PSA::Cache(3pm)>,
L<PSA(3pm)>

=cut
