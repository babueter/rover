#****************************************************************************
# Core routines for Rover
# By: Bryan Bueter, 07/12/2007
#
#****************************************************************************

package Rover::Core;
use Exporter;

use Rover::Core::FTP;
our $VERSION = "1.00";

BEGIN {
  @Rover::Core::ISA = qw( Exporter );
  @Rover::Core::EXPORT = qw( execute send put_file get_file );

  $Rover::Core::ftp_append_hostname = 1;
  $Rover::Core::command_timeout = 15;
}

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

sub execute {
  my ($self, $host, $command) = @_;

  $self->pinfo($host->hostname, "execute($command)\n");
  my $EOL = "\n";
  if ( $host->os eq "Windows" ) {
    $EOF = '';
  }

  $host->shell->clear_accum();
  $host->shell->send("$command $EOL");
  select(undef, undef, undef, 0.25);

  my $result = $host->shell->expect($Rover::Core::command_timeout, '-re', $self->user_prompt);

  if ( ! $result ) {
    $self->pinfo($host->hostname, "Error: execute: timed out running command, exiting with failure\n");
  }

  return($result);
}

sub send {
  my ($self, $host, $command) = @_;

  $self->pinfo($host->hostname, "send($command)\n");
  my $EOL = "\n";
  if ( $host->os eq "Windows" ) {
    $EOL = '';
  }

  $host->shell->send("$command $EOL");
  select(undef, undef, undef, 0.75);
  $host->shell->clear_accum();

  return(1);
}

sub put_file {
  my ($self, $host, $args) = @_;

  my ($local_file,$remote_file) = split(",",$args);
  $local_file =~ s/^[\t\s]*// ;
  $remote_file =~ s/^[\t\s]*// ;

  if ( $local_file eq "" ) { return( 0 ); }

  if ( $remote_file eq "" ) {
    my $file_name = ( split('/', $local_file) )[-1] ;
    $remote_file = "$local_file";
  }

  $self->pinfo($host->hostname, "put_file($local_file, $remote_file)\n");
  my $result = 0;
  my $put_file_routine = Rover::Core::FTP::determine_ftp_method($host, "put");
  if ( $put_file_routine ) {
    $result = &$put_file_routine($host, $local_file, $remote_file);
  } else {
    $self->pwarn($host->hostname() .":\tWarning: no FTP method available\n");
  }

  if ( ! $result ) {
    $self->pinfo($host->hostname(), "put_file: error: did not put file '$local_file' => '$remote_file'\n");
  }
  return($result);
}

sub get_file {
  my ($self, $host, $args) = @_;

  my ($remote_file,$local_file) = split(",",$args);
  $local_file =~ s/^[\t\s]*// ;
  $remote_file =~ s/^[\t\s]*// ;

  if ( $remote_file eq "" ) { return( 0 ); }

 # Fix $local_file name if it wasnt specified, and/or if it references
 # a directory.
 #
  if ( $local_file eq "" ) {
    my $file_name = ( split('/', $remote_file) )[-1] ;
    $local_file = $file_name;
  } elsif ( -d $local_file ) {
    my $file_name = ( split('/', $remote_file) )[-1] ;
    $local_file =~ s/\/$// ;
    $local_file .= "/$file_name";
  }

  if ( $Rover::Core::ftp_append_hostname ) {
    $local_file .= ".". $host->hostname ;
  }

  $self->pinfo($host->hostname, "get_file($remote_file, $local_file)\n");
  my $result = 0;
  my $get_file_routine = Rover::Core::FTP::determine_ftp_method($host, "get");
  if ( $get_file_routine ) {
    $result = &$get_file_routine($host, $remote_file, $local_file);
  } else {
    $self->pwarn($host->hostname() .":\tWarning: no FTP method available\n");
  }

  if ( ! $result ) {
    $self->pinfo($host->hostname(), "get_file: error: did not get file '$remote_file'\n");
  }
  return($result);
}

1;
