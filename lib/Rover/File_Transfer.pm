#****************************************************************************
# File_Transfer for rover
# By: Bryan Bueter, 09/10/2004
#
# Description: This module for Rover allows one to transfer files to a
# remote server by various means (sftp, ftp, or rcp).  The only functions
# exported to Rover are get_file and put_file.  Both functions determine
# the best means of puting or getting a file for the remote host specified.
#
# Functions contained are:
#
#	scan_open_port()	determine_file_transfer_method()
#	sftp_get_expect_obj()	sftp_put_file()		sftp_get_file()
#	scp_get_file()		scp_put_file()
#	ftp_get_obj()		ftp_put_file()		ftp_get_file()
#	rcp_put_file()		rcp_get_file()
#	put_file()		get_file()
#
# A breif description of the functions lies within.
#
# 09/14/2004
#   * bugfix: typo in scan_open_port fixed
#
#****************************************************************************

package Rover::File_Transfer;
use Exporter;
use Net::FTP;

use IPC::SysV qw(IPC_PRIVATE IPC_CREAT SEM_UNDO IPC_NOWAIT );
use IPC::Semaphore;

our $VERSION = "1.00";

@Rover::File_Transfer::ISA = qw( Exporter );
@Rover::File_Transfer::EXPORT = qw( get_file put_file );

BEGIN {
  $Rover::File_Transfer::append_hostname = 1;
  $Rover::File_Transfer::login_timeout = 5;
  $Rover::File_Transfer::transfer_timeout = 300;

  $Rover::File_Transfer::transfer_as_self = 0;
  $Rover::File_Transfer::rcp_as_self = 0;
  $Rover::File_Transfer::scp_on_failed_sftp = 0;

  $Rover::File_Transfer::preferred_protocol = undef;
  @Rover::File_Transfer::protocol_list = ("sftp","ftp","rcp");
  %Rover::File_Transfer::proto_ports = ("sftp" => 22, "ftp" => 21, "rcp" => 514);

  our (
    %ftp_expect_objects,
    %ftp_put_routines,
    %ftp_get_routines,

    $semaphore,
  );

  if ( $Rover::use_threads ) {
    Rover::pwarn("File_Transfer: Warning: only using protocol 'ftp' due to threads\n");

    @Rover::File_Transfer::protocol_list = ("ftp");
    $Rover::File_Transfer::semaphore = new IPC::Semaphore(IPC_PRIVATE, 10, IPC_CREAT) or die "Cant create semaphore\n";;
    $Rover::File_Transfer::semaphore->setall(32);
  }

  Rover::register_module("Rover::File_Transfer", qw( 
	$Rover::File_Transfer::append_hostname
	$Rover::File_Transfer::login_timeout
	$Rover::File_Transfer::transfer_timeout
	$Rover::File_Transfer::transfer_as_self
	$Rover::File_Transfer::rcp_as_self
	$Rover::File_Transfer::scp_on_failed_sftp
	$Rover::File_Transfer::preferred_protocol
	@Rover::File_Transfer::protocol_list ));

};

sub scan_open_port {
# Simple port scanner to determine of protocol port is open
#
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

sub determine_file_transfer_method {
# Determine based on preferred protocol list what file transfer
# method is available.  Returns the appropriate function based on
# method invoked (i.e. put or get).  Stores results globally so
# it should only check the port for a particular host once per run.
#
  my $hostname = shift;
  my $method = shift;

 # We already know what routine to use for this host.  Return the routine name
 #
  my $routines_variable = "Rover::File_Transfer::ftp_". $method ."_routines";
  if ( ${$routines_variable}{$hostname} ) {
    return ( ${$routines_variable}{$hostname} );
  }

 # Order the list of priorities by protocol name
 #
  my @preferred_protos = ();
  if ( $Rover::File_Transfer::preferred_protocol ne "" ) {
    Rover::pdebug("DEBUG: $hostname: file_transfer: determine_proto: preferring proto ". $Rover::File_Transfer::preferred_protocol ."\n");
    push (@preferred_protos,$Rover::File_Transfer::preferred_protocol);
  }
  foreach ( @Rover::File_Transfer::protocol_list ) {
    if ( $_ eq $Rover::File_Transfer::preferred_protocol ) { next; }
    push (@preferred_protos,$_);
  }

 # By protocol priority, check the port availability and set
 # the routine name accordingly
 #
  my $transfer_routine = undef;
  foreach my $proto ( @preferred_protos ) {
    if ( scan_open_port($hostname,$Rover::File_Transfer::proto_ports{$proto}) ) {
      $transfer_routine = $proto ."_". $method ."_file";
      last;
    }
    Rover::pdebug("DEBUG: $hostname: file_transfer: determine_proto: proto $proto not available\n");
  }

 # Return routine name, store the value for this host on later runs
 #
  if ( ! $transfer_routine ) {
    Rover::pdebug("DEBUG: $hostname: file_transfer: determine_proto: no method of transfer available\n");
    return(0);
  } else {
    my $put_routine = $transfer_routine;
    my $get_routine = $transfer_routine;

    $put_routine =~ s/_get_/_put_/ ;
    $get_routine =~ s/_put_/_get_/ ;

    if ( $Rover::use_threads ) {
      $Rover::File_Transfer::semaphore->op(0, -1, SEM_UNDO | IPC_NOWAIT);
    }
    $Rover::File_Transfer::ftp_put_routines{$hostname} = $put_routine;
    $Rover::File_Transfer::ftp_get_routines{$hostname} = $get_routine;
    if ( $Rover::use_threads ) {
      $Rover::File_Transfer::semaphore->op(0, 1, IPC_NOWAIT);
    }

    Rover::pdebug("DEBUG: $hostname: file_transfer: determine_proto: using function $transfer_routine for transfers\n");
    return($transfer_routine);
  }
}

#****************************************************************************
# SFTP Routines
#****************************************************************************
sub sftp_get_expect_obj {
# Create or return an sftp expect object.  Stores the results globally, so it
# should reuse the same object for multiple calls within a run.
#
  my $hostname = shift;

  if ( $Rover::File_Transfer::ftp_expect_objects{$hostname} != 0 ) {
    Rover::pdebug("DEBUG: file_transfer: sftp_get_expect_obj: Returning existing sftp expect object\n");
    return $Rover::File_Transfer::ftp_expect_objects{$hostname};
  }

  my $exp_obj;
  if ( $Rover::File_Transfer::transfer_as_self ) {
    $exp_obj = Expect->spawn("sftp $hostname")
      or die "Error: File_Transfer: Cannot spawn sftp object\n";

  } else {
    $exp_obj = Expect->spawn("sftp $Rover::user\@$hostname")
      or die "Error: File_Transfer: Cannot spawn sftp object\n";
  }

  $exp_obj->log_file("$Rover::logs_dir/$hostname.log");

  my @user_credentials = @Rover::user_credentials;
  my $starting_credentials = @user_credentials;

  my $spawn_ok = 0;
  my $logged_in = 1;
  my $failure_code;
  my $failure_count = 0;

  $exp_obj->expect($Rover::File_Transfer::login_timeout,
	[ qr'key fingerprint', sub { my $fh = shift;
		print $fh "yes\n";
		exp_continue; } ],
	[ 'yes\/no', sub { my $fh = shift;
		print $fh "yes\n";
		exp_continue; } ],
	[ 'ogin: $', sub { $spawn_ok = 1;
		my $fh = shift;
		print $fh "$Rover::user\n";
		exp_continue; } ],
	[ 'sername: $', sub { $spawn_ok = 1;
		my $fh = shift;
		print $fh "$Rover::user\n";
		exp_continue; } ],
	[ 'ermission [dD]enied', sub { $failure_count++; $logged_in = 0; $failure_code = 0; exp_continue; } ],
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
	[ eof => sub { if ($spawn_ok == 1) {
		  if ( $starting_credentials != $failure_count ) {
		    $logged_in = 0;
		    $failure_code = -1;
		  } else {
		    $logged_in = 0;
		    $failure_code = 0;
		  }
		} else {
		  $logged_in = 0;
		  $failure_code = -2;
		} } ],
	[ timeout => sub { $logged_in = 0; $failure_code = -1; } ],
	'-re', '^sftp( )*>\s', );

  $exp_obj->clear_accum();
  if ( ! $logged_in ) {
    Rover::pdebug("DEBUG: file_transfer: sftp_get_expect_obj: failed to get sftp object, code: $failure_code\n");

    if ( $Rover::use_threads ) {
      $Rover::File_Transfer::semaphore->op(0, -1, SEM_UNDO | IPC_NOWAIT);
    }
    $Rover::File_Transfer::ftp_expect_objects{$hostname} = -1;
    if ( $Rover::use_threads ) {
      $Rover::File_Transfer::semaphore->op(0, 1, IPC_NOWAIT);
    }
    return($failure_code);

  }

  if ( $Rover::use_threads ) {
    $Rover::File_Transfer::semaphore->op(0, -1, SEM_UNDO | IPC_NOWAIT);
  }
  $Rover::File_Transfer::ftp_expect_objects{$hostname} = $exp_obj;
  if ( $Rover::use_threads ) {
    $Rover::File_Transfer::semaphore->op(0, 1, IPC_NOWAIT);
  }

  return($exp_obj);
}

sub scp_put_file {
# put local_file to remote_file using scp
#
  my $hostname = shift;
  my $local_file = shift;
  my $remote_file = shift;

  my $scp_command = "";
  if ( ! $Rover::File_Transfer::transfer_as_self ) {
    $scp_command = "scp $local_file $Rover::user\@$hostname:$remote_file";
  } else {
    $scp_command = "scp $local_file $hostname:$remote_file";
  }

  my $got_file = 0;
  my @user_credentials = @Rover::user_credentials;
  while ( (my $pass = shift @user_credentials) && ! $got_file ) {

    my $exp_obj = Expect->spawn($scp_command)
      or die "Error: File_Transfer: Cannot spawn scp object\n";

    $exp_obj->log_file("$Rover::logs_dir/$hostname.log");

    $exp_obj->expect($Rover::File_Transfer::transfer_timeout,
        [ 'assword', sub { my $fh = shift;
		$fh->send("$pass\n");
		exp_continue; }, ],
        [ 'denied', sub { $got_file = 0; } ],
        [ 'lost connection', sub { $got_file = 0; } ],
        [ 'o such file', sub { $got_file = 0; } ],
        [ '100%', sub { $got_file = 1; } ],
        [ 'eof' => sub { $got_file = 1; }, ], );

    $exp_obj->hard_close();
  }

  if ( ! $got_file ) {
    Rover::pdebug("DEBUG: $hostname: file_transfer: scp_put: FAILED: $scp_command\n");
    return(0);
  }

  return(1);
}

sub sftp_put_file {
# put local_file to remote_file using sftp
#
  my $hostname = shift;
  my $local_file = shift;
  my $remote_file = shift;

  my $exp_obj = sftp_get_expect_obj($hostname);
  if ( ! $exp_obj ) { return(0); }

  if ( $exp_obj < 0 ) {
    if ( ! $Rover::File_Transfer::scp_on_failed_sftp ) { return(0); }

   # We tried to get an object but failed.  Try SCP
   #
    Rover::pwarn("$hostname:\tWarning: sftp_put_file: Could not get SFTP object, using SCP\n");
    my $status = scp_put_file($hostname, $local_file, $remote_file);
    return($status);
  }

  $exp_obj->send("put $local_file $remote_file\n");
  select(undef, undef, undef, 0.25);

  my $got_file = 1;
  $exp_obj->expect($Rover::File_Transfer::transfer_timeout,
	[ '^Couldn\'t get handle', sub { $got_file = 0; } ],
	[ qr'^File .* not found', sub { $got_file = 0; } ],
	[ '^Uploading ', sub { $got_file = 1; } ],
	'-re', '^sftp( )*>\s', );

  if ( ! $got_file ) {
    Rover::pdebug("DEBUG: $hostname: file_transfer: sftp_put: FAILED: put file '$local_file' -> '$remote_file'\n");
    return (0);
  }

  $exp_obj->clear_accum();

  $exp_obj->send("\r");
  select(undef, undef, undef, 0.25);
  $exp_obj->expect($Rover::File_Transfer::transfer_timeout,
	[ '^Couldn\'t get handle', sub { $got_file = 0; } ],
	'-re', '^sftp( )*>\s' );

 # Ok, this is extreme, but i've seen sftp die when you run
 # out of file space, so dont complain!
 #
  if ( ! $got_file ) {
    $exp_obj->send("quit\r");
    select(undef, undef, undef, $my_slow);
    $exp_obj->soft_close();
    $exp_obj = 0;

    if ( $Rover::use_threads ) {
      $Rover::File_Transfer::semaphore->op(0, -1, SEM_UNDO | IPC_NOWAIT);
    }
    $Rover::File_Transfer::ftp_expect_objects{$hostname} = undef;
    if ( $Rover::use_threads ) {
      $Rover::File_Transfer::semaphore->op(0, 1, IPC_NOWAIT);
    }
    Rover::pdebug("DEBUG: $hostname: file_transfer: sftp_put: FAILED: put file '$local_file' -> '$remote_file'\n");
    return 0;
  }

  Rover::pdebug("DEBUG: $hostname: file_transfer: sftp_put: put file '$local_file' -> '$remote_file'\n");
  return(1);
}

sub scp_get_file {
# get remote_file to local_file using scp
#
  my $hostname = shift;
  my $remote_file = shift;
  my $local_file = shift;

  my $scp_command = "";
  if ( ! $Rover::File_Transfer::transfer_as_self ) {
    $scp_command = "scp $Rover::user\@$hostname:$remote_file $local_file";
  } else {
    $scp_command = "scp $hostname:$remote_file $local_file";
  }

  my $got_file = 0;
  my @user_credentials = @Rover::user_credentials;
  while ( (my $pass = shift @user_credentials) && ! $got_file ) {

    my $exp_obj = Expect->spawn($scp_command)
      or die "Error: File_Transfer: Cannot spawn scp object\n";

    $exp_obj->log_file("$Rover::logs_dir/$hostname.log");

    $exp_obj->expect($Rover::File_Transfer::transfer_timeout,
        [ 'assword', sub { my $fh = shift;
		$fh->send("$pass\n");
		exp_continue; }, ],
        [ 'denied', sub { $got_file = 0; } ],
        [ 'lost connection', sub { $got_file = 0; } ],
        [ 'o such file', sub { $got_file = 0; } ],
        [ '100%', sub { $got_file = 1; } ],
        [ 'eof' => sub { $got_file = 1; }, ], );

    $exp_obj->hard_close();
  }

  if ( ! $got_file ) {
    Rover::pdebug("DEBUG: $hostname: file_transfer: scp_get: FAILED: $scp_command\n");
    return(0);
  }

  return(1);
}

sub sftp_get_file {
# get remote_file to local_file using sftp
#
  my $hostname = shift;
  my $remote_file = shift;
  my $local_file = shift;

  my $exp_obj = sftp_get_expect_obj($hostname);
  if ( ! $exp_obj ) { return(0); }

  if ( $exp_obj < 0 ) {
    if ( ! $Rover::File_Transfer::scp_on_failed_sftp ) { return(0); }

   # We tried to get an object but failed.  Try SCP
   #
    Rover::pwarn("$hostname:\tWarning: sftp_get: Could not get SFTP object, using SCP\n");
    my $status = scp_get_file($hostname, $remote_file, $local_file);
    return($status);
  }

  $exp_obj->send("get $remote_file $local_file\n");
  select(undef, undef, undef, 0.25);

  my $got_file = 1;
  $exp_obj->expect($Rover::File_Transfer::transfer_timeout,
	[ '^Couldn\'t get handle', sub { $got_file = 0; } ],
	[ '^Fetching ', sub { $got_file = 1; } ],
	'-re', '^sftp( )*>\s', );

  if ( ! $got_file ) {
    Rover::pdebug("DEBUG: $hostname: file_transfer: sftp_get: FAILED: get file '$remote_file' -> '$local_file'\n");
    return (0);
  }

  $exp_obj->clear_accum();

  $exp_obj->send("\r");
  select(undef, undef, undef, 0.25);
  $exp_obj->expect($Rover::File_Transfer::transfer_timeout,
	[ '^Couldn\'t get handle', sub { $got_file = 0; } ],
	'-re', '^sftp( )*>\s' );

 # Ok, this is extreme, but i've seen sftp die when you run
 # out of file space, so dont complain!
 #
  if ( ! $got_file ) {
    $exp_obj->send("quit\r");
    select(undef, undef, undef, $my_slow);
    $exp_obj->soft_close();
    $exp_obj = 0;

    if ( $Rover::use_threads ) {
      $Rover::File_Transfer::semaphore->op(0, -1, SEM_UNDO | IPC_NOWAIT);
    }
    $Rover::File_Transfer::ftp_expect_objects{$hostname} = undef;
    if ( $Rover::use_threads ) {
      $Rover::File_Transfer::semaphore->op(0, 1, IPC_NOWAIT);
    }
    Rover::pdebug("DEBUG: $hostname: file_transfer: sftp_get: FAILED: get file '$remote_file' -> '$local_file'\n");
    return 0;
  }

  Rover::pdebug("DEBUG: $hostname: file_transfer: sftp_get: got file '$remote_file' -> '$local_file'\n");
  return(1);
}

#****************************************************************************
# FTP Routines
#****************************************************************************
sub ftp_get_obj {
# Create or return a Net::FTP object.  It stores the results globally so it
# should re-use the object on multiple calls within the same run.
#
  my $hostname = shift;

  if ( $Rover::File_Transfer::ftp_expect_objects{$hostname} ) {
    return $Rover::File_Transfer::ftp_expect_objects{$hostname};
  }

  my $ftp_obj = Net::FTP->new($hostname);

  my $logged_in = 0;
  foreach my $pass (@Rover::user_credentials) {
    if ( $Rover::File_Transfer::transfer_as_self ) {
      if ( $ftp_obj->login($ENV{'USER'}, $pass) ) {
        $ftp_obj->binary;
        $logged_in = 1;
        last;
      }
    } else {
      if ( $ftp_obj->login($Rover::user, $pass) ) {
        $ftp_obj->binary;
        $logged_in = 1;
        last;
      }
    }
  }

  if ( ! $logged_in ) {
    Rover::pdebug("DEBUG: $hostname:\tftp_get_obj: ERROR: could not log in via FTP\n");
    return(0);
  }

  if ( $Rover::use_threads ) {
    $Rover::File_Transfer::semaphore->op(0, -1, SEM_UNDO | IPC_NOWAIT);
  }
  $Rover::File_Transfer::ftp_expect_objects{$hostname} = $ftp_obj;
  if ( $Rover::use_threads ) {
    $Rover::File_Transfer::semaphore->op(0, 1, IPC_NOWAIT);
  }
  return($ftp_obj);
}

sub ftp_put_file {
# put local_file to remote_file using ftp
#
  my $hostname = shift;
  my $local_file = shift;
  my $remote_file = shift;

  my $ftp_obj = ftp_get_obj($hostname);

  if ( ! $ftp_obj ) { return(0); }

  if ( ! $ftp_obj->put($local_file, $remote_file) ) {
    return(0);
  }

  return(1)
}

sub ftp_get_file {
# get remote_file to local_file using ftp
#
  my $hostname = shift;
  my $remote_file = shift;
  my $local_file = shift;

  my $ftp_obj = ftp_get_obj($hostname);

  if ( ! $ftp_obj->get($remote_file, $local_file) ) {
    return(0);
  }

  return(1)
}

#****************************************************************************
# RCP Routines
#****************************************************************************
sub rcp_put_file {
# Put local_file to remote_file using rcp+expect.  This does not re-use expect
# objects as the rcp program exits after completion
#
  my $hostname = shift;
  my $local_file = shift;
  my $remote_file = shift;

  if ( $Rover::File_Transfer::rcp_as_self ) {
    Rover::pwarn("Warning: Depreciated use of rcp_as_self, please use \$Rover::File_Transfer::transfer_as_self\n");
    $Rover::File_Transfer::transfer_as_self = 1;
  }

  my $rcp_command = "";
  if ( ! $Rover::File_Transfer::transfer_as_self ) {
    $rcp_command = "rcp $local_file $Rover::user\@$hostname:$remote_file";
  } else {
    $rcp_command = "rcp $local_file $hostname:$remote_file";
  }

  my $exp_obj = Expect->spawn($rcp_command)
    or die "Error: File_Transfer: Cannot spawn rcp object\n";

  $exp_obj->log_file("$Rover::logs_dir/$hostname.log");

  my $got_file = 1;
  $exp_obj->expect($Rover::File_Transfer::transfer_timeout,
	[ 'denied', sub { $got_file = 0; } ],
	'-re', 'eof', );

  if ( ! $got_file ) {
    Rover::pdebug("DEBUG: $hostname: file_transfer: rcp_put: FAILED: $rcp_command\n");
    return(0);
  }

  $exp_obj->soft_close();
  return(1);
}

sub rcp_get_file {
# Get remote_file to local_file using rcp+expect.  This does not re-use expect
# objects as the rcp program exits after completion
#
  my $hostname = shift;
  my $remote_file = shift;
  my $local_file = shift;

  if ( $Rover::File_Transfer::rcp_as_self ) {
    Rover::pwarn("Warning: Depreciated use of rcp_as_self, please use \$Rover::File_Transfer::transfer_as_self\n");
    $Rover::File_Transfer::transfer_as_self = 1;
  }

  my $rcp_command = "";
  if ( ! $Rover::File_Transfer::transfer_as_self ) {
    $rcp_command = "rcp $Rover::user\@$hostname:$remote_file $local_file";
  } else {
    $rcp_command = "rcp $hostname:$remote_file $local_file";
  }

  my $exp_obj = Expect->spawn($rcp_command)
    or die "Error: File_Transfer: Cannot spawn rcp object\n";

  $exp_obj->log_file("$Rover::logs_dir/$hostname.log");

  my $got_file = 1;
  $exp_obj->expect($Rover::File_Transfer::transfer_timeout,
        [ 'denied', sub { $got_file = 0; } ],
        '-re', 'eof', );

  if ( ! $got_file ) {
    Rover::pdebug("DEBUG: $hostname: file_transfer: rcp_get: FAILED: $rcp_command\n");
    return(0);
  }

  $exp_obj->soft_close();
  return(1);
}

sub put_file {
  my $args = shift;
  my $exp_obj = shift;
  my $hostname = shift;
  my $os = shift;

  my ($local_file,$remote_file) = split(",",$args);
  $local_file =~ s/^[\t\s]*// ;
  $local_file =~ s/[\t\s]*^// ;

  Rover::pdebug("DEBUG: $hostname:\tput_file: Puting local file $local_file => $remote_file\n");

  my $result = 0;
  my $put_file_routine = determine_file_transfer_method($hostname,"put");
  if ( $put_file_routine ) {
    $result = &$put_file_routine($hostname,$local_file,$remote_file);
  }

  if ( ! $result ) {
    Rover::pdebug("DEBUG: $hostname:\tfile_transfer: could not put local file '$local_file'\n");
  }
  return($result);
}

sub get_file {
  my $args = shift;
  my $exp_obj = shift;
  my $hostname = shift;
  my $os = shift;

  my ($remote_file,$local_file) = split(",",$args);
  $local_file =~ s/^[\t\s]*// ;
  $local_file =~ s/[\t\s]*^// ;
  if ( $Rover::File_Transfer::append_hostname ) {
    $local_file .= ".$hostname";
  }

  Rover::pdebug("DEBUG: $hostname:\tget_file: Getting remote file $remote_file => $local_file\n");

  my $result = 0;
  my $get_file_routine = determine_file_transfer_method($hostname,"get");
  if ( $get_file_routine ) {
    $result = &$get_file_routine($hostname,$remote_file,$local_file);
  }

  if ( ! $result ) {
    Rover::pdebug("DEBUG: $hostname: file_transfer: could not get remote file '$remote_file'\n");
  }
  return($result);
}

END {
  if ( $Rover::use_threads ) {
    $Rover::File_Transfer::semaphore->remove();
  }
};

1;
__END__

=head1 NAME

Rover::File_Transfer - File Transfer module for Rover

=head1 VERSION

1.00

=head1 SYNOPSYS

  # Format for commands.run
  GENERAL:{
    ...

    # Add module to rover runtime environment
    use File_Transfer.pm;
  };

  Ruleset:{
    ...

    # Get remote_file to local_file from remote host
    get_file(remote_file, local_file);

    # Put local_file to remote_file on remote host
    put_file (local_file, remote_file);

  };

File_Transfer will determine the best method of transferring the file
based on service availability and the value of
$File_Transfer::preferred_protocol.  The public functions available
are as follows:

  Rover::File_Transfer::put_file();
  Rover::File_Transfer::get_file();

Also these configuration variables can be set to manipulate the behavior of File_Transfer:

  $Rover::File_Transfer::append_hostname
  $Rover::File_Transfer::login_timeout
  $Rover::File_Transfer::transfer_timeout
  $Rover::File_Transfer::preferred_protocol
  $Rover::File_Transfer::transfer_as_self
  $Rover::File_Transfer::rcp_as_self
  $Rover::File_Transfer::scp_on_failed_sftp

=head1 DESCRIPTION

The basic use of this module is to include it in the Rover commands.run
file in the GENERAL section (use Rover::File_Transfer;) and then either
call get_file() or put_file() in any defined ruleset.  The file comes
with the default install of Rover and should be in place already.

=head1 USAGE

=over 4

=item put_file("local file","remote file");

Both can be relative paths to the file.  Note, however, that on the remote
side, assuming your $HOME directory is your CWD could be dangerous.  put_file
does not check the existance of either file, failures are detected by the
output of the file transfer commands.

=item get_file("remote file","local file");

Transfers the remote file to the local machine.  Again, files are not
checked for existance.

=head1 VARIABLES

=item $Rover::File_Transfer::append_hostname

Determines wether or not to append the remote host's name/ip to the local
filename.  This is handy when you want to get the same file from multiple
hosts and put them into one directory.  Default is true, set to 0 to disable.

=item $Rover::File_Transfer::login_timeout

Timeout value for failed login attempts.  Default value is 5 seconds.

=item $Rover::File_Transfer::transfer_timeout

How long to wait for a file transfer to complete.  This defaults to 300 seconds.

=item $Rover::File_Transfer::preferred_protocol

Acceptable values are "sftp" or "ftp".  This determines what protocol
of file transfer to "prefer" for each host.  File_Transfer will still check
the service and use an alternative protocol if this one is not available.

=item $Rover::File_Transfer::transfer_as_self

If set to 0, transfers will be done as the $Rover::user user.  If set to 1,
username will not be specified when calling file transfer programs.

=item $Rover::File_Transfer::rcp_as_self

This is depreciated for the $Rover::File_Transfer::transfer_as_self variable.

=item $Rover::File_Transfer::scp_on_failed_sftp

If ssh is listening on port 22, and sftp failes, setting this value to 1
will try to scp the file.  The default value of this is 0.

=head1 FAQ - Frequently Asked Questions

This is so far my own list, so this is sure to expand over time.

=head2 How can I force ftp over sftp?

You need to put the following line in the GENERAL section of the commands.run
configuration file:

        $Rover::File_Transfer::preferred_protocol = 'ftp';

=head2 I'm using expert mode in Rover, how do I use this function?

Three arguments are needed: 1. file name arguments, 2. expect object handle,
3. hostname.  Make sure to use the appropriate variables when calling
these routines, an example would be:

        put_file('local_file,remote_file', $exp_obj, $hostname);

=head2 I'm getting sftp protocol errors on only one server, is there any way I can force ftp on one server and still prefer sftp elsewhere?

Probably the best way to do this is to add the following to the GENERAL
section of commands.run:

        $Rover::File_Transfer::ftp_put_routines{'hostname'} = 'ftp_put_file';
        $Rover::File_Transfer::ftp_get_routines{'hostname'} = 'ftp_get_file';

This skips the process of determining what ftp service is available and forces
ftp for get and put on the particular hostname.

=head1 AUTHORS

Bryan Bueter (e-mail to come)

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
