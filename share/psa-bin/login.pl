
my $psa = shift;

my $q = $psa->request->get_param;

if ($q->{failed}) {
    $psa->run("/auth/only.pl") or return;
}

eval {
    my $ok;


    if ( my $username = $q->{u} ) {

	# attempt to load the login
	$username =~ s/^\s+|\s+$//g;
	$username =~ m/^\w+$/ or die \"EBADCHAR";

	my $r_user = $psa->storage->remote("BNZMV::MVUser");

	my (%users) = map { $_->username => $_ }
	    $psa->storage->select
		( $r_user,
		  ($r_user->{username} eq $username) |
		  ($r_user->{username} eq "superuser")
		);


    USER:
	for my $user ( values %users ) {

	    if ( $user->auth_ok($q->{p}) ) {
		my $is_super;
		if ( $is_super = $user->is_super ) {
		    delete $users{$user->username};
		    ($user) = values %users;
		}
		$psa->run("/session/open.pl", $user, $q->{p}, $is_super);
		$ok = 1;
		last USER;
	    }
	}

	die \"EFAIL" unless $ok;

    }

    if ( not $ok and $psa->sid ) {
	$psa->run("/session/resume.pl");
    }

    if ( $ok or $psa->heap_open && $psa->session->user ) {
	$psa->response->make_redirect
	    ($psa->request->uri(absolute => ($q->{next} || "/briefcase.pl")));
    } else {
	$psa->response->set_template([ Template => "login.html",
				       { } ]);
    }
};

my $err = $@ or return;
return $psa->run("/auth/bad.pl", $err);

=head1 NAME

psa-bin/login.pl - Handle login requests

=head1 INPUT PARAMETERS

=over

=item B<u>

The user-ID to attempt to login as.

=item B<p>

The password entered.

=item B<ssl>

The state of the SSL login tickbox (ignored)

=back

=head1 DESCRIPTION

This script attempts to authenticate a login.



=head1 OUTPUT TEMPLATES AND VARIABLES

=over

=item B<Success>: redirect to L<psa-bin/briefcase.pl>

Upon success the request is redirected to the briefcase main page.

=item B<Error>: F<templates/login.html> 

If there is an error, this template is called.

Variables:

=over

=item B<err>

A numeric error code

=item B<error>

An error message that may be presented to the user.

=item B<q>

The query parameters that were passed in.

=back


=back

=cut

