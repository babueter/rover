#****************************************************************************
# Shell_Routines module for Rover
# By: Bryan Bueter, 07/17/2007
#
#
#****************************************************************************

package Rover::Shell_Routines;
use Exporter;
use Expect;

$Expect::Log_Stdout = 0;

BEGIN {
  our $VERSION = "1.00";

  @Rover::Shell_Routines::ISA = qw( Exporter );
  @Rover::Shell_Routines::EXPORT = qw( shell_by_ssh shell_by_telnet shell_by_rlogin expect_login );

  $Rover::Shell_Routines::ssh_command = "ssh -x";
  $Rover::Shell_Routines::openssh_args = "-o ConnectTimeout=3 -o ForwardX11=no";

  $Rover::Shell_Routines::rlogin_as_self = 0;
  $Rover::Shell_Routines::use_net_telnet = 1;
  eval {
    require Net::Telnet;
  };
  if ( $@ ) {
    $Rover::Shell_Routines::use_net_telnet = 0;
  }

}

sub expect_login {
  my $self = shift;
  my $exp_obj = shift;
  my $user = shift;
  my @user_credentials = @_;

  my $logged_in = 1;    # Did we log in yet or not, default is true
  my $failure_code = 0; # Track the type of login failure
  my $spawn_ok = 0;     # Track if ssh actually responds for login procedure tracking
  my $changed_prompt = 0; # If we time out, change prompt only once

  $self->pdebug("DEBUG:\t\texpect_login attempting to gain shell for user $user with ". @user_credentials ." passwords\n");
  $logged_in = 1;
  $exp_obj->expect($self->login_timeout,
                  [ 'yes\/no', sub { my $fh = shift;
                        print $fh "yes\n";
                        exp_continue; } ],
                  [ 'ogin:([\s\t])*$', sub { $spawn_ok = 1;
                        my $fh = shift;
                        print $fh "$user\n";
                        exp_continue; } ],
                  [ 'sername:([\s\t])*$', sub { $spawn_ok = 1;
                        my $fh = shift;
                        print $fh "$user\n";
                        exp_continue; } ],
                  [ 'Connection timed out', sub { $logged_in = 0; $failure_code = -2; } ],
                  [ 'not allowed', sub { $logged_in = 0; $failure_code = 0; } ],
                  [ 'buffer_get', sub { $logged_in = 0; $failure_code = 0; } ],
                  [ 'ssh_exchange_identification', sub { $logged_in = 0; $failure_code = 0; } ],
                  [ 'assword:', sub { $pass = shift @user_credentials;
                        if ( ! $pass ) {
                          $logged_in = 0;
                          $failure_code = 0;
                          return(0);
                        }
                        $spawn_ok = 1;
                        my $fh = shift;
                        select(undef, undef, undef, 0.25);
                        $fh->clear_accum();
                        $fh->send("$pass\n");
                        select(undef, undef, undef, 0.25);
                        exp_continue; } ],
                  [ 'assphrase', sub { $pass = shift @user_credentials;
                        if ( ! $pass ) {
                          $logged_in = 0;
                          $failure_code = 0;
                          return(0);
                        }
                        $spawn_ok = 1;
                        my $fh = shift;
                        select(undef, undef, undef, 0.25);
                        $fh->clear_accum();
                        $fh->send("$pass\n");
                        select(undef, undef, undef, 0.25);
                        exp_continue; } ],
                  [ 'ew password', sub { $logged_in = 0; $failure_code = 0; } ],
                  [ 'Challenge', sub { $logged_in = 0; $failure_code = 0; } ],
                  [ 'Microsoft Windows', sub { $logged_in = 1; $self->user_prompt = '\\033\[2'; } ],
                  [ eof => sub { if ($spawn_ok == 1) {
                          $logged_in = 0;
                          $failure_code = -1;
                        } else {
                          $logged_in = 0;
                          $failure_code = -2;
                        } } ],
                  [ timeout => sub { if ( ! $changed_prompt && $spawn_ok ) {
                          $changed_prompt = 1;
                          $exp_obj->send("PS1='$self->user_prompt_force'\n\n");
                          select(undef,undef,undef,0.25);
                          exp_continue;
                        } else {
                          $logged_in = 0;
                          $failure_code = -1;
                        }} ],
                  '-re', $self->user_prompt, );

  if ( ! $logged_in ) {
    $self->pdebug("DEBUG:\t\tNot logged in, returning failure code: $failure_code\n");
    return($failure_code)
  };

  $self->pdebug("DEBUG:\t\tLog in successfull");
  return($exp_obj);

}

sub shell_by_ssh {
  my ($self, $host_obj) = @_;
  return 0 if ! $host_obj;

  $self->pdebug("DEBUG:\tShell_Routine ssh attempting to init shell for '". $host_obj->hostname ."'\n");
  if ( ! Rover::Core::scan_open_port($host_obj->hostname,"22") ) {
    $self->pdebug("DEBUG:\t\t$hostname: no ssh port opened\n");
    return(-2);
  }

  my $ssh_command = $Rover::Shell_Routines::ssh_command ;
  my @user_credentials;
  if ( ! $host_obj->passwords ) {
    @user_credentials = $self->user_credentials;
  } else {
    @user_credentials = $host_obj->passwords;
  }

 # We can force a shorter timeout for openssh which makes this worth the effort
 #
  open(SSH_VER,"ssh -V 2>&1 |");
  my $version_line = <SSH_VER>;
  close (SSH_VER);

  if ( $version_line =~ m/^OpenSSH_3.9/ ) {
    $ssh_command .= " ". $Rover::Shell_Routines::openssh_args ;
  }
  $ssh_command .= " -l ". $host_obj->username ." ". $host_obj->hostname;
  $self->pdebug("DEBUG:\t\tssh command compiled: '$ssh_command'\n");

 # Get logged in through our expect object
 #
  my $exp_obj = new Expect;
  $exp_obj->log_file($self->logs_dir ."/". $host_obj->hostname .".log", "w");
  $exp_obj->spawn($ssh_command) || $self->pdebug("DEBUG:\t\tcoud not spawn ssh command\n");

  my $return = $self->expect_login($exp_obj,$host_obj->username,@user_credentials);
  if ($return <= 0) {
    $self->pdebug("DEBUG:\t\t". $host_obj->hostname .": error returning result $return\n");
    if ($return == -1) {
     # Sometimes ssh closes on the first failed attempt, queue the
     # next password and call expect_login again
     #
      $self->pdebug("DEBUG:\t\t". $host_obj->hostname .": ssh died before exhausting password list, respawning\n");
      while ($return == -1 && shift @user_credentials) {
        $exp_obj->hard_close();

        $exp_obj = new Expect;
        $exp_obj = Expect->spawn($ssh_command);
        $exp_obj->log_file($self->logs_dir ."/". $host_obj->hostname .".log","w");
        $return = $self->expect_login($exp_obj,$host_obj->username,@user_credentials);
        $self->pdebug("DEBUG:\t\t". $host_obj->hostname .": re-ran expect_login, return code was $return\n");
      }
    }
  }

  $host_obj->shell($return);

  return($return);
}

sub shell_by_telnet {
  my ($self, $host_obj) = @_;
  return 0 if ! $host_obj;

  $self->pdebug("DEBUG:\tShell_Routine telnet attempting to init shell for '". $host_obj->hostname ."'\n");
  if ( ! Rover::Core::scan_open_port($host_obj->hostname,"22") ) {
    $self->pdebug("DEBUG:\t\t$hostname: no ssh port opened\n");
    return(-2);
  }

  my $exp_obj = undef;
  my $success = 0;
  my @user_credentials;
  if ( ! $host_obj->passwords ) {
    @user_credentials = $self->user_credentials;
  } else {
    @user_credentials = $host_obj->passwords;
  }
  if ( $Rover::Shell_Routines::use_net_telnet ) {
    my $t;
    my $password = shift @user_credentials;

    while ($password && ! $success) {
      $t = new Net::Telnet (Timeout => $self->login_timeout,
				Prompt => "/". $self->user_prompt ."/",
				Input_log => $self->logs_dir ."/". $host_obj->hostname .".log");

     # We could probably change Errmode on our Net::Telnet so we wouldnt have
     # to eval open and login, but I wasnt sure if I would have to $t->close
     # and clean up afterwards so....
     #
      eval {
        $t->open($host_obj->hostname);
        $t->login($host_obj->username, $password);
      };
      if ( $@ ) {
        $password = shift @user_credentials;
      } else {
        $success = 1;
      }
    }

    if ( $success ) {
      $exp_obj = Expect->exp_init( $t ) or print "003\n";
      $exp_obj->log_file( $self->logs_dir ."/". $host_obj->hostname .".log" );
    }

  } else {
   # Almost everyone should have Net::Telnet, but just in case...
   #
    $exp_obj = new Expect;
    $exp_obj->log_file( $self->logs_dir ."/". $host_obj->hostname .".log", "w");
    $exp_obj->spawn("telnet ". $host_obj->hostname);

    $success = $self->expect_login($exp_obj,$host_obj->username,@user_credentials);

  }

  if ( $success ) {
    $host_obj->shell( $exp_obj );
  } else {
    $host_obj->shell( 0 );
  }

  return( $success );
}

sub shell_by_rlogin {
  my ($self, $host_obj) = @_;
  return 0 if ! $host_obj;

  $self->pdebug("DEBUG:\tShell_Routine rlogin attempting to init shell for '". $host_obj->hostname ."'\n");
  if ( !  Rover::Core::scan_open_port($host_obj->hostname,"513") ) {
    $self->pdebug("DEBUG:\t\t$hostname: no rlogin port opened\n");
    return(-2);
  }

  my $exp_obj = new Expect;
  $exp_obj->log_file($self->logs_dir ."/". $host_obj->hostname .".log","w");
  if ( $Rover::Shell_Routines::rlogin_as_self ) {
    $exp_obj->spawn("rlogin ". $host_obj->hostname);
  } else {
    $exp_obj->spawn("rlogin ". $host_obj->hostname ." -l ". $host_obj->username);
  }


  my @user_credentials;
  if ( ! $host_obj->passwords ) {
    @user_credentials = $self->user_credentials;
  } else {
    @user_credentials = $host_obj->passwords;
  }
  my $spawn_ok = 0;
  my $logged_in = 1;
  my $result = 1;
  my $changed_prompt = 0;
  my $first_password = shift @user_credentials;
  $exp_obj->expect($self->login_timeout,
        [ 'assword', sub { if ( $spawn_ok ) {
                          $first_password = shift @user_credentials;
                          if ( $first_password eq "" ) {
                            $logged_in = 0;
                          } else {
                            my $fh = shift;
                            $fh->send("$first_password\n");
                            select(undef,undef,undef,0.25);
                            exp_continue;
                          }
                        } else {
                          $spawn_ok = 1;
                          my $fh = shift;
                          $fh->send("$first_password\n");
                          select(undef,undef,undef,0.25);
                          exp_continue;
                        }} ],
        [ 'invalid', sub { $logged_in = 0; } ],
        [ 'ogin incorrect', sub { $logged_in = 0; } ],
        [ 'not allowed', sub { $logged_in = 0; $result = 0; } ],
        [ timeout => sub { if ( ! $changed_prompt ) {
                          $changed_prompt = 1;
                          $exp_obj->send("PS1='$user->user_prompt_force'\n\n");
                          select(undef,undef,undef,0.25);
                          exp_continue;
                        } else {
                          $logged_in = 0; $result = -1;
                        }} ],
        '-re', $self->user_prompt, );

  if ( ! $logged_in ) {
    if ( $result > 0 ) {
      $result = $self->expect_login($exp_obj,$host_obj->username,@user_credentials);
    }
  }

  if ($result > 0) {
    $host_obj->shell( $exp_obj );
  }
  return($result);
}

1;

__END__
