#****************************************************************************
# Password for rover
# By: Bryan Bueter, 08/05/2004
#
#****************************************************************************

package Password;
use Exporter;

our $VERSION = "1.00";

@Password::ISA = qw( Exporter );
@Password::EXPORT = qw( passwd );

BEGIN {
  $Password::new_password = undef;
};

sub read_new_password {
  system("stty -echo");
  print STDERR "\n";
  print STDERR "Changing password for $Rover::user\n";

  print STDERR "$Rover::user New password: ";
  $Password::new_password = <STDIN>;
  chomp $Password::new_password;

  print STDERR "\nRe-enter $Rover::user new password: ";
  my $verify_password = <STDIN>;
  chomp $verify_password;

  print STDERR "\n";

  while ( $Password::new_password ne $verify_password ) {
    print STDERR "\nPasswords do not match, try again.\n";

    print STDERR "$Rover::user New password: ";
    $Password::new_password = <STDIN>;
    chomp $Password::new_password;

    print STDERR "\nRe-enter $Rover::user new password: ";
    $verify_password = <STDIN>;
    chomp $verify_password;

    print STDERR "\n";
  }
  print STDERR "\n";
  system("stty echo");
}

sub passwd {
  my $command = shift;
  my $exp_obj = shift;
  my $hostname = shift;
  my $os = shift;

  if ( ! $Password::new_password ) {
    if ( ! $command ) {
      print "Error: passwd(): no password supplied, cannot continue\n";
      return(0);
    }
    $Password::new_password = $command;
  }
  if ( $Rover::root_access_required ) {
    print "Error: passwd(): cannot be ran as root, use unlock() instead\n";
    return(0);
  }

  my $changed_password = 1;
  my $sent_password = 0;
  my $user_password_correct = 0;
  my @user_credentials = @Rover::user_credentials;

  foreach my $user_password ( @user_credentials ) {
    $exp_obj->send("passwd \n");
    select(undef,undef,undef,0.25);

    $exp_obj->expect(7,
	[  qr/pick/ , sub { my $fh = shift;
		select(undef,undef,undef,0.25);
		print $fh "p\n";
		select(undef, undef, undef, $0.25);
		exp_continue; } ],
	[ qr/old password:/i , sub { my $fh = shift;
		print $fh "$user_password\n";
		exp_continue; } ],
	[ qr/current.? (unix )?password:/i , sub { my $fh = shift;
		print $fh "$user_password\n";
		exp_continue; } ],
	[ qr/ login password:/ , sub { my $fh = shift;
		print $fh "$user_password\n";
		exp_continue; } ],
	[ qr/assword again:/ , sub { my $fh = shift;
		$user_password_correct = 1;
		print $fh "$Password::new_password\n";
		select(undef,undef,undef,0.25);
		$sent_password++;
		exp_continue; } ],
	[ qr/new (unix )?password:/i, sub { my $fh = shift;
		$user_password_correct = 1;
		print $fh "$Password::new_password\n";
		select(undef,undef,undef,0.25);
		$sent_password++;
		exp_continue; } ],
	[ qr/sorry/i , sub { $changed_password = 0;
		print "$hostname:\tWarning: passwd: old password incorrect\n" if $Rover::debug > 1;
		} ],
	[ 'must contain', sub { $changed_password = 0;
		print "$hostname:\tError: unlock: Password does not meet requirements\n" if $Rover::debug;
		} ],
	[ 'do([\s]*n.t) match', sub { $changed_password = 0;
		print "$hostname:\tError: unlock: internal error, please report!\n" if $Rover::debug;
		} ],
	[ 'at least', sub { $changed_password = 0;
		print "$hostname:\tError: unlock: Password does not meet requirements\n" if $Rover::debug;
		} ],
	[ 'not contain enough', sub { $changed_password = 0;
		print "$hostname:\tError: unlock: Password does not meet requirements\n" if $Rover::debug;
		} ],
	[ 'too short', sub { $changed_password = 0;
		print "$hostname:\tError: unlock: Password does not meet requirements\n" if $Rover::debug;
		} ],
	[ 'minimum', sub { $changed_password = 0;
		print "$hostname:\tError: unlock: Password does not meet requirements\n" if $Rover::debug;
		} ],
	[ 're-use', sub { $changed_password = 0;
		print "$hostname:\tWarning: unlock: Password previusly used\n" if $Rover::debug > 1;
		} ],
	[ 'reuse', sub { $changed_password = 0;
		print "$hostname:\tWarning: unlock: Password previusly used\n" if $Rover::debug > 1;
		} ],
	[ eof => sub { $changed_password = 0; } ],
	[ timeout => sub { $changed_password = 0; } ],
	'-re', $Rover::user_prompt,
    );
    if ( $user_password_correct ) { last; }
  }

  if ( $changed_password ) {
    return(1);
  } else {
    return(0);
  }
}

1;
