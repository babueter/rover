#****************************************************************************
# Core::FTP module for Rover
# By: Bryan Bueter, 07/17/2007
#
#
#****************************************************************************

package Rover::Core::FTP;
use Exporter;
use Net::FTP;

BEGIN {
  our $VERSION = "1.00";

  @Rover::Core::FTP::methods = ("sftp", "ftp", "rcp");
  %Rover::Core::FTP::method_ports = ("sftp" => 22, "ftp" => 21, "rcp" => 514);

  $Rover::Core::FTP::login_as_self = 0;
  $Rover::Core::FTP::login_timeout = 10;
}

sub determine_ftp_method {
# Determine what FTP method is available.  Return appropriate
# function based on method invoked (i.e. put or get).  Store the
# results in the host object
  my ($host_obj, $method) = @_;

  if ( $host_obj->ftp_method_used ) {
    my $method_used = $host_obj->ftp_method_used;
    my $routine = $method_used ."_". $method ;

    return ("Rover::Core::FTP::". $routine);
  }

  my @preferred_methods = $host_obj->ftp_methods;
  if ( ! @preferred_methods ) {
    @preferred_methods = @Rover::Core::FTP::methods;
  }

 # By protocol priority, check the port availability and set
 # the routine name accordingly
  my $ftp_method = undef;
  foreach my $proto ( @preferred_methods ) {
    if ( Rover::Core::scan_open_port($host_obj->hostname, $Rover::Core::FTP::method_ports{$proto}) ) {
      $ftp_method = $proto ."_". $method ;
      last;
    }
  }
  if ( ! $ftp_method ) { return (0); };

  $host_obj->ftp_method_used($proto);
  return("Rover::Core::FTP::". $ftp_method);
}

############################################################
# SFTP put, get, and setup methods
############################################################
sub sftp_put {
  my ($host_obj, $local_file, $remote_file) = @_;

  if ( ! $host_obj->ftp() ) {
    if ( ! sftp_setup($host_obj) ) {
      return(0);
    }
  }

  my $exp_obj = $host_obj->ftp();
  $exp_obj->send("put $local_file $remote_file\n");
  select(undef, undef, undef, 0.25);

  my $got_file = 1;
  $exp_obj->expect($Rover::File_Transfer::transfer_timeout,
        [ '^Couldn\'t get handle', sub { $got_file = 0; } ],
        [ '^Fetching ', sub { $got_file = 1; } ],
        '-re', '^sftp( )*>\s', );

  if ( ! $got_file ) {
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

    return( $host_obj->ftp(0) );
  }

  return(1);
}

sub sftp_get {
  my ($host_obj, $remote_file, $local_file) = @_;

  if ( ! $host_obj->ftp() ) {
    if ( ! sftp_setup($host_obj) ) {
      return(0);
    }
  }

  my $exp_obj = $host_obj->ftp();
  $exp_obj->send("get $remote_file $local_file\n");
  select(undef, undef, undef, 0.25);

  my $got_file = 1;
  $exp_obj->expect($Rover::File_Transfer::transfer_timeout,
        [ '^Couldn\'t get handle', sub { $got_file = 0; } ],
        [ '^Fetching ', sub { $got_file = 1; } ],
        '-re', '^sftp( )*>\s', );

  if ( ! $got_file ) {
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

    return( $host_obj->ftp(0) );
  }

  return(1);
}

sub sftp_setup {
  my $self = shift;
  my $host = shift;
  my $host_obj = $self->host($host);

  my $exp_obj = new Expect;
  if ( $Rover::Core::FTP::login_as_self ) {
    $exp_obj->spawn("sftp ". $host_obj->hostname);

  } else {
    $exp_obj->spawn("sftp ". $host_obj->username() ."@". $host_obj->hostname);
  
  }

  my @passwords = $host_obj->passwords();
  if ( ! @passwords ) { @passwords = $self->user_credentials; }
  my $starting_credentials = @passwords;

  my $spawn_ok = 0;
  my $logged_in = 1;
  my $failure_code;
  my $failure_count = 0;

  $exp_obj->expect($Rover::Core::FTP::login_timeout,
        [ qr'key fingerprint', sub { my $fh = shift;
                print $fh "yes\n";
                exp_continue; } ],
        [ 'yes\/no', sub { my $fh = shift;
                print $fh "yes\n";
                exp_continue; } ],
        [ 'ogin: $', sub { $spawn_ok = 1;
                my $fh = shift;
                print $fh $host_obj->username ."\n";
                exp_continue; } ],
        [ 'sername: $', sub { $spawn_ok = 1;
                my $fh = shift;
                print $fh $host_obj->username ."\n";
                exp_continue; } ],
        [ 'ermission [dD]enied', sub { $failure_count++; $logged_in = 0; $failure_code = 0; exp_continue; } ],
        [ 'buffer_get', sub { $logged_in = 0; $failure_code = 0; } ],
        [ 'ssh_exchange_identification', sub { $logged_in = 0; $failure_code = 0; } ],
        [ 'assword:', sub { $pass = shift @passwords;
                if ( ! $pass ) {
                  $logged_in = 0;
                  $failure_code = -1;
                  return(0);
                }
                $spawn_ok = 1;
                my $fh = shift;
                select(undef, undef, undef, 0.25);
                $fh->clear_accum();
                $fh->send("$pass\n");
                select(undef, undef, undef, 0.25);
                exp_continue; } ],
        [ 'assphrase', sub { $pass = shift @passwords;
                if ( ! $pass ) {
                  $logged_in = 0;
                  $failure_code = -1;
                  return(0);
                }
                $spawn_ok = 1;
                my $fh = shift;
                select(undef, undef, undef, 0.25);
                $fh->clear_accum();
                $fh->send("$pass\n");
                select(undef, undef, undef, 0.25);
                exp_continue; } ],
        [ 'ew password', sub { $logged_in = 0; $failure_code = -1; } ],
        [ 'Challenge', sub { $logged_in = 0; $failure_code = -1; } ],
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
        '-re', '^sftp[ ]*>\s', );

  $exp_obj->clear_accum();
  if ( ! $logged_in ) {
    $host_obj->ftp(0);
    return($failure_code);
  }

  $host_obj->ftp_method_used("sftp");
  return( $host_obj->ftp($exp_obj) );
}

############################################################
# FTP put, get, and setup methods
############################################################

sub ftp_put {
  my ($host_obj, $local_file, $remote_file) = @_;

  if ( ! $host_obj->ftp() ) {
    if ( ! ftp_setup($host_obj) ) {
      return(0);
    }
  }

  $ftp_obj = $host_obj->ftp();
  if ( ! $ftp_obj->put($local_file, $remote_file) ) {
    return(0);
  }
  return(1);
}

sub ftp_get {
   my ($host_obj, $remote_file, $local_file) = @_;

  if ( ! $host_obj->ftp() ) {
    if ( ! ftp_setup($host_obj) ) {
      return(0);
    }
  }

  $ftp_obj = $host_obj->ftp();
  if ( ! $ftp_obj->get($remote_file, $local_file) ) {
    return(0);
  }
  return(1);
}

sub ftp_setup {
  my $self = shift;
  my $host = shift;
  my $host_obj = $self->host($host);

  my $ftp_obj = Net::FTP->new($host_obj->hostname());

  my $logged_in = 0;
  my @passwords = $host_obj->passwords;
  if ( ! @passwords ) { @passwords = $self->user_credentials(); }

  foreach my $pass (@passwords) {
    if ( $Rover::Core::FTP::login_as_self ) {
      if ( $ftp_obj->login($ENV{'USER'}, $pass) ) {
        $ftp_obj->binary;
        $logged_in = 1;
        last;
      }
    } else {
      if ( $ftp_obj->login($host_obj->username, $pass) ) {
        $ftp_obj->binary;
        $logged_in = 1;
        last;
      }
    }
  }

  if ( ! $logged_in ) {
    return(0);
  }

  $host_obj->ftp_method_used("ftp");
  return( $host_obj->ftp($ftp_obj) );
}


1;
