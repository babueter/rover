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

  $File_Trnasfer::preferred_protocol = undef;
  @File_Transfer::protocol_list = ("sftp","ftp");
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
    $remote = IO::Socket::INET->new(
      Proto => "tcp",
      PeerAddr => $hostname,
      PeerPort => "($port)",
    ) or die $@ ;
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

  if ( $File_Transfer::ftp_expect_objects{$hostname} ) {
    print "\tDEBUG: file_transfer: sftp_get_expect_obj: Returning existing sftp expect object\n" if $Rover::debug > 1;
    return $File_Transfer::ftp_expect_objects{$hostname};
  }

  my $exp_obj = Expect->spawn("sftp $Rover::user\@$hostname")
    or die "Error: File_Transfer: Cannot spawn sftp object\n";

  $exp_obj->log_file("$Rover::logs_dir/$hostname.log");

  my @user_credentials = @Rover::user_credentials;
  my $spawn_ok = 0;
  my $logged_in = 1;
  my $failure_code;

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
		  $logged_in = 0;
		  $failure_code = 0;
		} else {
		  $logged_in = 0;
		  $failure_code = -2;
		} } ],
	[ timeout => sub { $logged_in = 0; $failure_code = -1; } ],
	'-re', '^sftp( )*>\s', );

  $exp_obj->clear_accum();
  if ( ! $logged_in ) {
    print "\tDEBUG: file_transfer: sftp_get_expect_obj: failed to get sftp object, code: $failure_code\n" if $Rover::debug > 1;
    
    return(0);
  }

  $File_Transfer::ftp_expect_objects{$hostname} = $exp_obj;
  return($exp_obj);
}

sub sftp_put_file {
# put local_file to remote_file using sftp
#
  my $hostname = shift;
  my $local_file = shift;
  my $remote_file = shift;

  my $exp_obj = sftp_get_expect_obj($hostname);
  if ( ! $exp_obj ) { return(0); }

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

sub sftp_get_file {
# get remote_file to local_file using sftp
#
  my $hostname = shift;
  my $remote_file = shift;
  my $local_file = shift;

  my $exp_obj = sftp_get_expect_obj($hostname);
  if ( ! $exp_obj ) { return(0); }

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

  foreach my $pass (@Rover::user_credentials) {
    if ( $ftp_obj->login($Rover::user, $pass) ) {
      $ftp_obj->binary;
      $logged_in = 1;
      last;
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

}
sub rcp_get_file {
# Get remote_file to local_file using rcp+expect.  This does not re-use expect
# objects as the rcp program exits after completion
#
  my $hostname = shift;
  my $remote_file = shift;
  my $local_file = shift;

}

sub put_file {
  my $args = shift;
  my $exp_obj = shift;
  my $hostname = shift;
  my $os = shift;

  my ($local_file,$remote_file) = split(",",$args);

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
