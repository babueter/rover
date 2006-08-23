#****************************************************************************
# Password for rover
# By: Bryan Bueter, 08/05/2004
#
#****************************************************************************

package Rover::Password;
use Exporter;

our $VERSION = "1.00";

@Rover::Password::ISA = qw( Exporter );
@Rover::Password::EXPORT = qw( passwd );

BEGIN {
  $Rover::Password::new_password = undef;

  Rover::register_module("Rover::Password");
};

sub tty_read_new_password {
  system("stty -echo");
  print STDERR "\n";
  print STDERR "Changing password for $Rover::user\n";

  print STDERR "$Rover::user New password: ";
  $Rover::Password::new_password = <STDIN>;
  chomp $Rover::Password::new_password;

  print STDERR "\nRe-enter $Rover::user new password: ";
  my $verify_password = <STDIN>;
  chomp $verify_password;

  print STDERR "\n";

  while ( $Rover::Password::new_password ne $verify_password ) {
    print STDERR "\nRover::Password do not match, try again.\n";

    print STDERR "$Rover::user New password: ";
    $Rover::Password::new_password = <STDIN>;
    chomp $Rover::Password::new_password;

    print STDERR "\nRe-enter $Rover::user new password: ";
    $verify_password = <STDIN>;
    chomp $verify_password;

    print STDERR "\n";
  }
  print STDERR "\n";
  system("stty echo");
}

sub gtkconfig {
  my $window = new Gtk::Window();
  $window->set_title("Rover::Password GTK Config");
  $window->set_policy($false, $false, $true);

  my $config_vbox = new Gtk::VBox($false, 0);
  $window->add($config_vbox);
  $config_vbox->show();

  my $config_hbox1 = new Gtk::HBox($false, 0);
  $config_vbox->pack_start($config_hbox1, $false, $false, 2);
  $config_hbox1->show();

  my $config_password_label = new Gtk::Label("New Password: ");
  $config_hbox1->pack_start($config_password_label, $false, $false, 2);
  $config_password_label->show();

  my $config_password = new Gtk::Entry(100);
  $config_password->set_visibility( $false );
  $config_hbox1->pack_start($config_password, $true, $true, 2);
  $config_password->show();

  my $config_hbox2 = new Gtk::HBox($false, 0);
  $config_vbox->pack_start($config_hbox2, $false, $false, 2);
  $config_hbox2->show();

  my $config_verify_password_label = new Gtk::Label("Verify Password: ");
  $config_hbox2->pack_start($config_verify_password_label, $false, $false, 2);
  $config_verify_password_label->show();

  my $config_verify_password = new Gtk::Entry(100);
  $config_verify_password->set_visibility( $false );
  $config_hbox2->pack_start($config_verify_password, $true, $true, 2);
  $config_verify_password->show();

  my $separator = new Gtk::HSeparator();
  $config_vbox->pack_start($separator, $false, $true, 2);
  $separator->show();

  my $config_bbox = new Gtk::HButtonBox();
  $config_bbox->set_layout_default('spread');
  $config_vbox->pack_start($config_bbox, $false, $false, 0);
  $config_bbox->show();

  my $config_ok = new Gtk::Button("Ok");
  $config_bbox->add($config_ok);
  $config_ok->show();

  my $config_done = new Gtk::Button("Done");
  $config_bbox->add($config_done);
  $config_done->show();

  $config_done->signal_connect('clicked', sub { my $widget = shift; $widget->parent->parent->parent->destroy(); });
  $config_ok->signal_connect('clicked', sub {
	my ($widget, $config_password, $config_verify_password) = @_ ;

	my $password = $config_password->get_text();
	my $verify_password = $config_verify_password->get_text();

	$config_password->set_text("");
	$config_verify_password->set_text("");

	if ( $password ne $verify_password ) {
		Rover::perror("Passwords do not match\n");
		return(0);
	}

	$Rover::Password::new_password = $password;
	Rover::perror("Password set successfully\n");

	return(0);
  }, $config_password, $config_verify_password);

  $window->show();
  $window->set_modal( $true );
}

sub passwd {
  my $command = shift;
  my $exp_obj = shift;
  my $hostname = shift;
  my $os = shift;

  if ( ! $Rover::Password::new_password ) {
    if ( ! $command ) {
      Rover::pinfo($hostname, "Error, no password supplied.");
      return(0);
    }
    $Rover::Password::new_password = $command;
  }
  if ( $Rover::root_access_required ) {
    Rover::pinfo($hostname, "Error, passwd() cannot be ran as root.");
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
		print $fh "$Rover::Password::new_password\n";
		select(undef,undef,undef,0.25);
		$sent_password++;
		exp_continue; } ],
	[ qr/new (unix )?password:/i, sub { my $fh = shift;
		$user_password_correct = 1;
		print $fh "$Rover::Password::new_password\n";
		select(undef,undef,undef,0.25);
		$sent_password++;
		exp_continue; } ],
	[ qr/sorry/i , sub { $changed_password = 0;
		Rover::pinfo($hostname, "Error in passwd(), old password incorrect");
		} ],
	[ 'must contain', sub { $changed_password = 0;
		Rover::pinfo($hostname, "Error in passwd(), new password does not meet requirements");
		} ],
	[ 'Bad password', sub { $changed_password = 0;
		Rover::pinfo($hostname, "Error in passwd(), new password does not meet requirements");
		} ],
	[ 'unchanged', sub { $changed_password = 0;
		Rover::pinfo($hostname, "Error in passwd(), new password does not meet requirements");
		} ],
	[ 'do([\s]*n.t) match', sub { $changed_password = 0;
		Rover::pinfo($hostname, "Error in passwd(), internal error, please report");
		} ],
	[ 'at least', sub { $changed_password = 0;
		Rover::pinfo($hostname, "Error in passwd(), new password does not meet requirements");
		} ],
	[ 'not contain enough', sub { $changed_password = 0;
		Rover::pinfo($hostname, "Error in passwd(), new password does not meet requirements");
		} ],
	[ 'too short', sub { $changed_password = 0;
		Rover::pinfo($hostname, "Error in passwd(), new password does not meet requirements");
		} ],
	[ 'minimum', sub { $changed_password = 0;
		Rover::pinfo($hostname, "Error in passwd(), new password does not meet requirements");
		} ],
	[ 're-use', sub { $changed_password = 0;
		Rover::pinfo($hostname, "Error in passwd(), new password does not meet requirements");
		} ],
	[ 'reuse', sub { $changed_password = 0;
		Rover::pinfo($hostname, "Error in passwd(), new password does not meet requirements");
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
__END__

=head1 NAME

Rover::Password - Run passwd command as normal user

=head1 VERSION

1.00

=head1 SYNOPSYS

  # Format for commands.run
  GENERAL:{
    ...

    # Add module to rover runtime environment
    use Rover::Password;

    # Optionally you can have the new password read
    # from the command line:
    Rover::Password::tty_read_new_password();
  };

  Ruleset:{
    ...

    # Change password of the current user
    passwd();

  };

The public functions available are as follows:

  Rover::Password::passwd()
  Rover::Password::read_new_password()

=head1 DESCRIPTION

  This module provides a means of changing the password for 
  a normal user.  This command does not work with root access
  and will fail if it is detected.  This only works with the
  currently logged on user (i.e. $Rover::user).

=head1 USAGE

=over 4

=item passwd();

  Change password for normal user.  There are two options to supplying
  rover the password, one is to pass it in plain text as an argument
  within commands.run.  The other is to call read_new_password() prior
  to calling passwd().

=item tty_read_new_password();

  This will store the password for the passwd() routine without having
  to put it in a plain text file.  You will be prompted for the password
  as soon as you call this function.

  The preferred method is to call this within the GENERAL ruleset definition.

=head1 AUTHORS

Bryan Bueter

=head1 LICENSE

This module can be used under the same license as Perl.

=head1 DISCLAIMER

THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
DAMAGE.
