
package PSA::Audit;

use strict;
use base qw(Class::Tangram);
use warnings;
use Sys::Hostname;

=head1 NAME

Audit - an auditable system event

=head1 SYNOPSIS

 my $event = new Audit();
 $event->from($psa);

=head1 DESCRIPTION

Audit events - define default values, etc.

=cut

our $hostname;

sub new {
    my $class = shift;

    my $self = $class->SUPER::new(@_);

    $self->guess_host() unless $self->host;

    return $self;
}

sub guess_host {
    my $self = shift;
    $self->set_host( $hostname ||= hostname );
}

sub from {
    my $self = shift;;
    my $psa = shift;

    $self->set_sid(substr($psa->sid, 0, 32));
    $self->set_remote_addr($psa->request->remote_addr);
    $self->set_source($psa->storage->site_name);
    $self->set_subsystem(substr($psa->request->filename, 0, 32));
}

use constant HIDE => qw(sid remote_addr host subsystem source);

our $schema =
    {
     'fields' => {
		  'dmdatetime' => {
				   'when' => {
					      'sql' => 'TIMESTAMP'
					     }
				  },
		  'string' => {
			       'sid' => {
					 'sql' => 'VARCHAR(32)'
					},
			       'err_code' => {
					      'sql' => 'VARCHAR(16)'
					     },
			       'source' => {
					    'sql' => 'VARCHAR(32)'
					   },
			       'host' => {
					  'sql' => 'VARCHAR(15)'
					 },
			       'remote_addr' => {
						 'sql' => 'VARCHAR(48)'
						},
			       'subsystem' => {
					       'sql' => 'CHAR(32)'
					      }
			      }
		 }
    }
;

Class::Tangram::import_schema(__PACKAGE__);
1;
