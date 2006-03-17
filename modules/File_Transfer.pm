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

package File_Transfer;
use Exporter;
use Net::FTP;

our $VERSION = "1.00";

@File_Transfer::ISA = qw( Exporter );
@File_Transfer::EXPORT = qw( get_file put_file );

BEGIN {
  $File_Transfer::append_hostname = 1;
  $File_Transfer::login_timeout = 5;
  $File_Transfer::transfer_timeout = 300;

  $File_Transfer::transfer_as_self = 0;
  $File_Transfer::rcp_as_self = 0;
  $File_Transfer::scp_on_failed_sftp = 0;

  $File_Transfer::preferred_protocol = undef;
  @File_Transfer::protocol_list = ("sftp","ftp","rcp");
  %File_Transfer::proto_ports = ("sftp" => 22, "ftp" => 21, "rcp" => 514);

  %File_Transfer::ftp_expect_objects;
  %File_Transfer::ftp_put_routines;
  %File_Transfer::ftp_get_routines;

  if ( $Rover::use_threads ) {
    die "File_Transfer module is NOT thread safe, exiting\n";
  }
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
  my $routines_variable = "File_Transfer::ftp_". $method ."_routines";
  if ( ${$routines_variable}{$hostname} ) {
    return ( ${$routines_variable}{$hostname} );
  }

 # Order the list of priorities by protocol name
 #
  my @preferred_protos = ();
  if ( $File_Transfer::preferred_protocol ne "" ) {
    print "\tDEBUG: $hostname: file_transfer: determine_proto: preferring proto ". $File_Transfer::preferred_protocol ."\n"
      if $Rover::debug > 1;
    push (@preferred_protos,$File_Transfer::preferred_protocol);
  }
  foreach ( @File_Transfer::protocol_list ) {
    if ( $_ eq $File_Transfer::preferred_protocol ) { next; }
    push (@preferred_protos,$_);
  }

 # By protocol priority, check the port availability and set
 # the routine name accordingly
 #
  my $transfer_routine = undef;
  foreach my $proto ( @preferred_protos ) {
    if ( scan_open_port($hostname,$File_Transfer::proto_ports{$proto}) ) {
      $transfer_routine = $proto ."_". $method ."_file";
      last;
    }
    print "\tDEBUG: $hostname: file_transfer: determine_proto: proto $proto not available\n" if $Rover::debug > 1;
  }

 # Return routine name, store the value for this host on later runs
 #
  if ( ! $transfer_routine ) {
    print "\tDEBUG: $hostname: file_transfer: determine_proto: no method of transfer available\n" if $Rover::debug > 1;
    return(0);
  } else {
    my $put_routine = $transfer_routine;
    my $get_routine = $transfer_routine;

    $put_routine =~ s/_get_/_put_/ ;
    $get_routine =~ s/_put_/_get_/ ;

    $File_Transfer::ftp_put_routines{$hostname} = $put_routine;
    $File_Transfer::ftp_get_routines{$hostname} = $get_routine;

    print "\tDEBUG: $hostname: file_transfer: determine_proto: using function $transfer_routine for transfers\n" if $Rover::debug > 1;
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

  if ( $File_Transfer::ftp_expect_objects{$hostname} != 0 ) {
    print "\tDEBUG: file_transfer: sftp_get_expect_obj: Returning existing sftp expect object\n" if $Rover::debug > 1;
    return $File_Transfer::ftp_expect_objects{$hostname};
  }

  my $exp_obj;
  if ( $File_Transfer::transfer_as_self ) {
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

  $exp_obj->expect($File_Transfer::login_timeout,
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
    print "\tDEBUG: file_transfer: sftp_get_expect_obj: failed to get sftp object, code: $failure_code\n" if $Rover::debug > 1;

    $File_Transfer::ftp_expect_objects{$hostname} = -1;
    return($failure_code);
  }

  $File_Transfer::ftp_expect_objects{$hostname} = $exp_obj;
  return($exp_obj);
}

sub scp_put_file {
# put local_file to remote_file using scp
#
  my $hostname = shift;
  my $local_file = shift;
  my $remote_file = shift;

  my $scp_command = "";
  if ( ! $File_Transfer::transfer_as_self ) {
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

    $exp_obj->expect($File_Transfer::transfer_timeout,
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
    print "$hostname:\tfile_transfer: scp_put: FAILED: $scp_command\n" if $Rover::debug > 1;
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
    if ( ! $File_Transfer::scp_on_failed_sftp ) { return(0); }

   # We tried to get an object but failed.  Try SCP
   #
    print "$hostname:\tWarning: sftp_put_file: Could not get SFTP object, using SCP\n" if $Rover::debug > 0;
    my $status = scp_put_file($hostname, $local_file, $remote_file);
    return($status);
  }

  $exp_obj->send("put $local_file $remote_file\n");
  select(undef, undef, undef, 0.25);

  my $got_file = 1;
  $exp_obj->expect($File_Transfer::transfer_timeout,
	[ '^Couldn\'t get handle', sub { $got_file = 0; } ],
	[ qr'^File .* not found', sub { $got_file = 0; } ],
	[ '^Uploading ', sub { $got_file = 1; } ],
	'-re', '^sftp( )*>\s', );

  if ( ! $got_file ) {
    print "$hostname:\tfile_transfer: sftp_put: FAILED: put file '$local_file' -> '$remote_file'\n" if $Rover::debug > 1;
    return (0);
  }

  $exp_obj->clear_accum();

  $exp_obj->send("\r");
  select(undef, undef, undef, 0.25);
  $exp_obj->expect($File_Transfer::transfer_timeout,
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

    $File_Transfer::ftp_expect_objects{$hostname} = undef;
    print "$hostname:\tfile_transfer: sftp_put: FAILED: put file '$local_file' -> '$remote_file'\n" if $Rover::debug > 1;
    return 0;
  }

  print "$hostname:\tfile_transfer: sftp_put: put file '$local_file' -> '$remote_file'\n" if $Rover::debug > 1;
  return(1);
}

sub scp_get_file {
# get remote_file to local_file using scp
#
  my $hostname = shift;
  my $remote_file = shift;
  my $local_file = shift;

  my $scp_command = "";
  if ( ! $File_Transfer::transfer_as_self ) {
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

    $exp_obj->expect($File_Transfer::transfer_timeout,
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
    print "$hostname:\tfile_transfer: scp_get: FAILED: $scp_command\n" if $Rover::debug > 1;
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
    if ( ! $File_Transfer::scp_on_failed_sftp ) { return(0); }

   # We tried to get an object but failed.  Try SCP
   #
    print "$hostname:\tWarning: sftp_get: Could not get SFTP object, using SCP\n" if $Rover::debug > 0;
    my $status = scp_get_file($hostname, $remote_file, $local_file);
    return($status);
  }

  $exp_obj->send("get $remote_file $local_file\n");
  select(undef, undef, undef, 0.25);

  my $got_file = 1;
  $exp_obj->expect($File_Transfer::transfer_timeout,
	[ '^Couldn\'t get handle', sub { $got_file = 0; } ],
	[ '^Fetching ', sub { $got_file = 1; } ],
	'-re', '^sftp( )*>\s', );

  if ( ! $got_file ) {
    print "$hostname:\tfile_transfer: sftp_get: FAILED: get file '$remote_file' -> '$local_file'\n" if $Rover::debug > 1;
    return (0);
  }

  $exp_obj->clear_accum();

  $exp_obj->send("\r");
  select(undef, undef, undef, 0.25);
  $exp_obj->expect($File_Transfer::transfer_timeout,
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

    $File_Transfer::ftp_expect_objects{$hostname} = undef;
    print "$hostname:\tfile_transfer: sftp_get: FAILED: get file '$remote_file' -> '$local_file'\n" if $Rover::debug > 1;
    return 0;
  }

  print "$hostname:\tfile_transfer: sftp_get: got file '$remote_file' -> '$local_file'\n" if $Rover::debug > 1;
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

  if ( $File_Transfer::ftp_expect_objects{$hostname} ) {
    return $File_Transfer::ftp_expect_objects{$hostname};
  }

  my $ftp_obj = Net::FTP->new($hostname);

  my $logged_in = 0;
  foreach my $pass (@Rover::user_credentials) {
    if ( $File_Transfer::transfer_as_self ) {
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
    print "$hostname:\tftp_get_obj: ERROR: could not log in via FTP\n" if $Rover::debug > 1;
    return(0);
  }

  $File_Transfer::ftp_expect_objects{$hostname} = $ftp_obj;
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

  if ( $File_Transfer::rcp_as_self ) {
    print "Warning: Depreciated use of rcp_as_self, please use \$File_Transfer::transfer_as_self\n";
    $File_Transfer::transfer_as_self = 1;
  }

  my $rcp_command = "";
  if ( ! $File_Transfer::transfer_as_self ) {
    $rcp_command = "rcp $local_file $Rover::user\@$hostname:$remote_file";
  } else {
    $rcp_command = "rcp $local_file $hostname:$remote_file";
  }

  my $exp_obj = Expect->spawn($rcp_command)
    or die "Error: File_Transfer: Cannot spawn rcp object\n";

  $exp_obj->log_file("$Rover::logs_dir/$hostname.log");

  my $got_file = 1;
  $exp_obj->expect($File_Transfer::transfer_timeout,
	[ 'denied', sub { $got_file = 0; } ],
	'-re', 'eof', );

  if ( ! $got_file ) {
    print "$hostname:\tfile_transfer: rcp_put: FAILED: $rcp_command\n" if $Rover::debug > 1;
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

  if ( $File_Transfer::rcp_as_self ) {
    print "Warning: Depreciated use of rcp_as_self, please use \$File_Transfer::transfer_as_self\n";
    $File_Transfer::transfer_as_self = 1;
  }

  my $rcp_command = "";
  if ( ! $File_Transfer::transfer_as_self ) {
    $rcp_command = "rcp $Rover::user\@$hostname:$remote_file $local_file";
  } else {
    $rcp_command = "rcp $hostname:$remote_file $local_file";
  }

  my $exp_obj = Expect->spawn($rcp_command)
    or die "Error: File_Transfer: Cannot spawn rcp object\n";

  $exp_obj->log_file("$Rover::logs_dir/$hostname.log");

  my $got_file = 1;
  $exp_obj->expect($File_Transfer::transfer_timeout,
        [ 'denied', sub { $got_file = 0; } ],
        '-re', 'eof', );

  if ( ! $got_file ) {
    print "$hostname:\tfile_transfer: rcp_get: FAILED: $rcp_command\n" if $Rover::debug > 1;
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

  my $result = 0;
  my $put_file_routine = determine_file_transfer_method($hostname,put);
  if ( $put_file_routine ) {
    $result = &$put_file_routine($hostname,$local_file,$remote_file);
  }

  if ( ! $result ) {
    print "$hostname:\tfile_transfer: could not put local file '$local_file'\n";
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
  if ( $File_Transfer::append_hostname ) {
    $local_file .= ".$hostname";
  }

  my $result = 0;
  my $get_file_routine = determine_file_transfer_method($hostname,get);
  if ( $get_file_routine ) {
    $result = &$get_file_routine($hostname,$remote_file,$local_file);
  }

  if ( ! $result ) {
    print "$hostname:\tfile_transfer: could not get remote file '$remote_file'\n";
  }
  return($result);
}

1;
