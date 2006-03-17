#****************************************************************************
# Shell_Access_Routines for Rover
# By: Bryan Bueter, 09/08/2004
#
# 09/14/2004
#   * bugfix: typo in scan_open_port fixed
#   * bugfix: fixed timing issues with setting PS1 variable
#
#****************************************************************************

package Shell_Access_Routines;
use Exporter;

our $VERSION = "1.00";

BEGIN {
  @Shell_Access_Routines::ISA = qw( Exporter );
  @Shell_Access_Routines::EXPORT = qw( shell_by_ssh shell_by_telnet shell_by_rlogin );

  $Shell_Access_Routines::login_timeout = 7;
  $Shell_Access_Routines::my_slow = 0.25;

  $Shell_Access_Routines::rlogin_as_self = 0;
  $Shell_Access_Routines::use_net_telnet = 1;

  push(@Rover::shell_access_routines, "shell_by_ssh");
  push(@Rover::shell_access_routines, "shell_by_telnet");
  push(@Rover::shell_access_routines, "shell_by_rlogin");

  eval {
    require Net::Telnet;
  };
  if ( $@ ) {
    print "Warning: Net::Telnet not available, will spawn telnet if needed.\n";
    $Shell_Access_Routines::use_net_telnet = 0;
  }

};

sub scan_open_port {
  my $hostname = shift;
  my $port = shift;

  require IO::Socket;

  my $remote;
  eval {
    local $SIG{ALRM} = sub { die "scan_open_port: failed to connect to $port\n"; };
    alarm 2;
    $remote = IO::Socket::INET->new(
      Proto => "tcp",
      PeerAddr => $hostname,
      PeerPort => "($port)",
    ) or die $@ ;
    alarm 0;
  };

  if ( ! $@ ) {
    return(1);
  } else {
    return(0);
  }
}

sub execute_login {
  my $exp_obj = shift;
  my $user = shift;
  my @user_credentials = @_;

  my $logged_in = 1;    # Did we log in yet or not, default is true
  my $failure_code;     # Track the type of login failure
  my $spawn_ok = 0;     # Track if ssh actually responds for login procedure tracking
  my $changed_prompt = 0; # If we time out, change prompt only once

  $logged_in = 1;
  $exp_obj->expect($Shell_Access_Routines::login_timeout,
                  [ 'key fingerprint', sub { my $fh = shift;
                        print $fh "yes\n";
                        exp_continue; } ],
                  [ 'yes\/no', sub { my $fh = shift;
                        print $fh "yes\n";
                        exp_continue; } ],
                  [ 'ogin:([\s\t])*$', sub { $spawn_ok = 1;
                        my $fh = shift;
                        print $fh "$Rover::user\n";
                        exp_continue; } ],
                  [ 'sername:([\s\t])*$', sub { $spawn_ok = 1;
                        my $fh = shift;
                        print $fh "$Rover::user\n";
                        exp_continue; } ],
                  [ 'not allowed', sub { $logged_in = 0; $failure_code = 0; } ],
                  [ 'buffer_get', sub { $logged_in = 0; $failure_code = 0; } ],
                  [ 'ssh_exchange_identification', sub { $logged_in = 0; $failure_code = 0; } ],
                  [ 'assword', sub { $pass = shift @user_credentials;
                        if ( ! $pass ) {
                          $logged_in = 0;
                          $failure_code = 0;
                          return(0);
                        }
                        $spawn_ok = 1;
                        my $fh = shift;
                        select(undef, undef, undef, $Shell_Access_Routines::my_slow);
                        $fh->clear_accum();
                        $fh->send("$pass\n");
                        select(undef, undef, undef, $Shell_Access_Routines::my_slow);
                        exp_continue; } ],
                  [ 'assphrase', sub { $pass = shift @user_credentials;
                        if ( ! $pass ) {
                          $logged_in = 0;
                          $failure_code = 0;
                          return(0);
                        }
                        $spawn_ok = 1;
                        my $fh = shift;
                        select(undef, undef, undef, $Shell_Access_Routines::my_slow);
                        $fh->clear_accum();
                        $fh->send("$pass\n");
                        select(undef, undef, undef, $Shell_Access_Routines::my_slow);
                        exp_continue; } ],
                  [ 'ew password', sub { $logged_in = 0; $failure_code = 0; } ],
                  [ 'Challenge', sub { $logged_in = 0; $failure_code = 0; } ],
                  [ 'Microsoft Windows', sub { $logged_in = 1; $Rover::user_prompt = '\\033\[2'; } ],
                  [ eof => sub { if ($spawn_ok == 1) {
                          $logged_in = 0;
                          $failure_code = -1;
                        } else {
                          $logged_in = 0;
                          $failure_code = -2;
                        } } ],
                  [ timeout => sub { if ( ! $changed_prompt && $spawn_ok ) {
                          $changed_prompt = 1;
                          $exp_obj->send("PS1='$Rover::user_prompt_force'\n\n");
                          select(undef,undef,undef,0.25);
                          exp_continue;
                        } else {
                          $logged_in = 0;
                        }} ],
                  '-re', $Rover::user_prompt, );

  if ( ! $logged_in ) { return($failure_code) };

  return(1);

}

sub shell_by_ssh {
  my $hostname = shift;
  my $user = shift;
  my @user_credentials = @_;

  if ( ! scan_open_port($hostname,"22") ) {
    return(-2);
  }

  my $exp_obj = new Expect;
  $exp_obj->exp_internal(1);
  $exp_obj = Expect->spawn("ssh -l $user $hostname");

  $exp_obj->log_file("$Rover::logs_dir/$hostname.log","w");

  my $result = execute_login($exp_obj,$user,@user_credentials);
  if ($result > 0) {
    return($exp_obj);
  } else {
    if ($result == -1) {
     # Sometimes ssh closes on the first failed attempt, queue the
     # next password and call execute_login again
     #
      print "\tDEBUG: ssh died before exhausting passord list, respawining\n" if $Rover::debug > 1;
      while ($result <= 0 && shift @user_credentials) {
        $exp_obj->hard_close();

        $exp_obj = new Expect;
        $exp_obj->exp_internal(1);
        $exp_obj = Expect->spawn("ssh -l $user $hostname");
        $exp_obj->log_file("$Rover::logs_dir/$hostname.log","w");
        $result = execute_login($exp_obj,$user,@user_credentials);
      }
    }
    return($result);
  }
}

sub shell_by_telnet {
  my $hostname = shift;
  my $user = shift;
  my @user_credentials = @_;

  if ( ! scan_open_port($hostname,"23") ) {
    return(-2);
  }

  my $exp_obj = undef;
  my $success;
  if ( $Shell_Access_Routines::use_net_telnet ) {
    my $t;
    my $password = shift @user_credentials;

    $success = 0;
    while ($password && ! $success) {
      $t = new Net::Telnet (Timeout => $Shell_Access_Routines::login_timeout,
				Prompt => "/$Rover::user_prompt/",
				Dump_Log => "$Rover::logs_dir/$hostname.log");

     # We could probably change Errmode on our Net::Telnet so we wouldnt have
     # to eval open and login, but I wasnt sure if I would have to $t->close
     # and clean up afterwards so....
     #
      eval { 
        $t->open($hostname);
        $t->login($user, $password);
      };
      if ( $@ ) {
        $password = shift @user_credentials;
      } else {
        $success = 1;
      }
    }
    $exp_obj = Expect->exp_init( $t );
    $exp_obj->log_file("$Rover::logs_dir/$hostname.log","w");

  } else {
   # Almost everyone should have Net::Telnet, but just in case...
   #
    $exp_obj = new Expect;
    $exp_obj->exp_internal(1);
    $exp_obj = Expect->spawn("telnet $hostname");

    my $success = execute_login($exp_obj,$user,@user_credentials);
  }

  if ( $success > 0) {
    return($exp_obj);
  } else {
    return($success);
  }
}

sub shell_by_rlogin {
  my $hostname = shift;
  my $user = shift;
  my @user_credentials = @_;

  if ( ! scan_open_port($hostname,"513") ) {
    return(-2);
  }

  my $exp_obj = new Expect;
  $exp_obj->exp_internal(1);
  if ( $Shell_Access_Routines::rlogin_as_self ) {
    $exp_obj = Expect->spawn("rlogin $hostname");
  } else {
    $exp_obj = Expect->spawn("rlogin $hostname -l $Rover::user");
  }

  $exp_obj->log_file("$Rover::logs_dir/$hostname.log","w");

  my $spawn_ok = 0;
  my $logged_in = 1;
  my $result = 1;
  my $changed_prompt = 0;
  my $first_password = shift @user_credentials;
  $exp_obj->expect($Shell_Access_Routines::login_timeout,
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
			  $exp_obj->send("PS1='$Rover::user_prompt_force'\n\n");
			  select(undef,undef,undef,0.25);
			  exp_continue;
			} else {
			  $logged_in = 0; $result = -1; 
			}} ],
	'-re', $Rover::user_prompt, );

  if ( ! $logged_in ) {
    if ( $result > 0 ) {
      $result = execute_login($exp_obj,$user,@user_credentials);
    }
  }

  if ($result > 0) {
    return($exp_obj);
  } else {
    return($result);
  }
}

1;
