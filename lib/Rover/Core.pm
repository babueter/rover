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
  @Rover::Core::EXPORT = qw( execute send put_file get_file passwd unlock useradd );

  @Rover::Core::DESCRIPTION = "Core routines for Rover"; 
  @Rover::Core::ROVER_VARS = qw(
	$Rover::Core::ftp_append_hostname
	$Rover::Core::command_timeout
	@Rover::Core::FTP::methods
	%Rover::Core::FTP::method_ports
	$Rover::Core::FTP::login_as_self 
	$Rover::Core::FTP::login_timeout
  );

  $Rover::Core::ftp_append_hostname = 1;
  $Rover::Core::command_timeout = 15;
}

sub scan_open_port {
# Scan to see if the remote port is open
#
  my $hostname = shift;
  my $port = shift;

  require IO::Socket;

 # Open the socket in an eval so we can use a SIGALRM timeout
 #
  eval {
    local $SIG{ALRM} = sub { die "scan_open_port: failed to connect to $port\n"; };
    alarm 2;
    my $remote = IO::Socket::INET->new(
      Proto => "tcp",
      PeerAddr => $hostname,
      PeerPort => "($port)",
    ) or die $@ ;
    alarm 0;
    close($remote);
  };

  if ( ! $@ ) {
    return(1);	# Success
  } else {
    return(0);	# Failure
  }
}

sub execute {
# Send the supplied command over the expect object, expect users prompt
#
  my ($self, $host, $command) = @_;

  my $host_obj = $self->host($host) || return(0);

  $self->pinfo($host, "execute($command)\n");
  my $EOL = "\n";
  if ( $host_obj->os eq "Windows" ) {
    $EOF = '';
  }

  $host_obj->shell->clear_accum();
  $host_obj->shell->send("$command $EOL");
  select(undef, undef, undef, 0.25);

  my $result = $host_obj->shell->expect($Rover::Core::command_timeout, '-re', $self->user_prompt);

  if ( ! $result ) {
    $self->pinfo($host, "Error: execute: timed out running command, exiting with failure\n");
  }

  return($result);
}

sub send {
# Send the supplied command over the expect object, expect no response
#
  my ($self, $host, $command) = @_;

  my $host_obj = $self->host($host) || return(0);

  $self->pinfo($host, "send($command)\n");
  my $EOL = "\n";
  if ( $host_obj->os eq "Windows" ) {
    $EOL = '';
  }

  $host_obj->shell->send("$command $EOL");
  select(undef, undef, undef, 0.75);
  $host_obj->shell->clear_accum();

  return(1);
}

sub put_file {
# Put a local file onto the remote server
#
  my ($self, $host, $args) = @_;

  my $host_obj = $self->host($host) || return(0);

 # We put a comma on the end in case the user doesnt supply a remote file name
 #
  my ($local_file,$remote_file) = split(",",$args.",");
  $local_file =~ s/^[\t\s]*// ;
  $remote_file =~ s/^[\t\s]*// ;

  if ( $local_file eq "" ) { return( 0 ); }

 # If no remote file is specified, steal the name from the local file and send it
 # to the remote PWD
 #
  if ( $remote_file eq "" ) {
    my $file_name = ( split('/', $local_file) )[-1] ;
    $remote_file = "$local_file";
  }

 # Send the file based on the pre-determined file transfer method
 #
  $self->pinfo($host, "put_file($local_file, $remote_file)\n");
  my $result = 0;
  my $put_file_routine = Rover::Core::FTP::determine_ftp_method($host_obj, "put");
  if ( $put_file_routine ) {
    $result = &$put_file_routine($host_obj, $local_file, $remote_file);
  } else {
    $self->pwarn($host .":\tWarning: no FTP method available\n");
  }

  if ( ! $result ) {
    $self->pinfo($host, "put_file: error: did not put file '$local_file' => '$remote_file'\n");
  }
  return($result);
}

sub get_file {
# Retrieve a remote file and copy it locally
#
  my ($self, $host, $args) = @_;

  my $host_obj = $self->host($host) || return(0);

 # We put a comma on the end in case the user doesnt supply a local file name
 #
  my ($remote_file,$local_file) = split(",",$args.",");
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
    $local_file .= ".". $host;
  }

 # Get the remote file based on the pre-determined file transfer method
 #
  $self->pinfo($host, "get_file($remote_file, $local_file)\n");
  my $result = 0;
  my $get_file_routine = Rover::Core::FTP::determine_ftp_method($host_obj, "get");
  if ( $get_file_routine ) {
    $result = &$get_file_routine($host_obj, $remote_file, $local_file);
  } else {
    $self->pwarn($host .":\tWarning: no FTP method available\n");
  }

  if ( ! $result ) {
    $self->pinfo($host, "get_file: error: did not get file '$remote_file'\n");
  }
  return($result);
}

sub passwd {
  my ($self, $host, $pass) = @_;

  $self->pinfo($host, "passwd(...)\n");
  my $host_obj = $self->host($host);

  if ( ! defined($pass) ) {
    $self->pinfo($host, "No password supplied\n");
    return(0);
  }

  my $changed_password = 1;
  my $sent_password = 0;
  my $user_password_correct = 0;
  my @user_credentials = $self->user_credentials;

  foreach my $user_password ( @user_credentials ) {
    $host_obj->shell->send("passwd \n");
    select(undef,undef,undef,0.25);

    $host_obj->shell->expect(7,
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
                print $fh "$pass\n";
                select(undef,undef,undef,0.25);
                $sent_password++;
                exp_continue; } ],
        [ qr/new (unix )?password:/i, sub { my $fh = shift;
                $user_password_correct = 1;
                print $fh "$pass\n";
                select(undef,undef,undef,0.25);
                $sent_password++;
                exp_continue; } ],
        [ qr/sorry/i , sub { $changed_password = 0;
                $self->pinfo($host, "Error in passwd(), old password incorrect");
                } ],
        [ 'must contain', sub { $changed_password = 0;
                $self->pinfo($host, "Error in passwd(), new password does not meet requirements");
                } ],
        [ 'Bad password', sub { $changed_password = 0;
                $self->pinfo($host, "Error in passwd(), new password does not meet requirements");
                } ],
        [ 'unchanged', sub { $changed_password = 0;
                $self->pinfo($host, "Error in passwd(), new password does not meet requirements");
                } ],
        [ 'do([\s]*n.t) match', sub { $changed_password = 0;
                $self->pinfo($host, "Error in passwd(), internal error, please report");
                } ],
        [ 'at least', sub { $changed_password = 0;
                $self->pinfo($host, "Error in passwd(), new password does not meet requirements");
                } ],
        [ 'not contain enough', sub { $changed_password = 0;
                $self->pinfo($host, "Error in passwd(), new password does not meet requirements");
                } ],
        [ 'too short', sub { $changed_password = 0;
                $self->pinfo($host, "Error in passwd(), new password does not meet requirements");
                } ],
        [ 'minimum', sub { $changed_password = 0;
                $self->pinfo($host, "Error in passwd(), new password does not meet requirements");
                } ],
        [ 're-use', sub { $changed_password = 0;
                $self->pinfo($host, "Error in passwd(), new password does not meet requirements");
                } ],
        [ 'reuse', sub { $changed_password = 0;
                $self->pinfo($host, "Error in passwd(), new password does not meet requirements");
                } ],
        [ eof => sub { $changed_password = 0; } ],
        [ timeout => sub { $changed_password = 0; } ],
        '-re', $self->user_prompt,
    );
    if ( $user_password_correct ) { last; }
  }

  if ( $changed_password ) {
    return(1);
  } else {
    return(0);
  }
}

sub unlock {
  my ($self, $host, $command) = @_;

  my $host_obj = $self->host($host);
  my $os = $host_obj->os();

  my ($res_username, $res_password) = split(/\,/, $command, 2);
  $res_username =~ s/ //g;
  $res_password =~ s/ //g;

  if ( $res_username eq '' ) {
    $self->pinfo($host, "Error in unlock, no username specified");
    return(0);
  }
  $self->pinfo($host, "unlock($res_username,...)\n");

   # OS specific unlock commands
   #
    if ( $os eq "HP_UX") {
        $host_obj->shell->send("/usr/lbin/modprpw -k $res_username\n");
        select(undef,undef,undef,0.25);
        $host_obj->shell->expect(5, '-re', $self->user_prompt);
    } elsif ( $os eq "AIX" ) {
        $host_obj->shell->send("/usr/bin/chsec -f /etc/security/lastlog -a \"unsuccessful_login_count=0\" -s $res_username\n");
        select(undef,undef,undef,0.25);
        $host_obj->shell->expect(5, '-re', $self->user_prompt);
        
        $host_obj->shell->send("/usr/bin/chuser account_locked='false' login='true' $res_username\n");
        select(undef,undef,undef,0.25);
        $host_obj->shell->expect(5, '-re', $self->user_prompt);
    }
        
    my $changed_password = 0;
    $host_obj->shell->send("passwd $res_username\n");
    select(undef,undef,undef,0.25);
 
    my $sent_password = 0;
    $host_obj->shell->expect(7,
        [  qr'pick', sub { select(undef,undef,undef,0.25);
                $fh->send("p\n");
                select(undef, undef, undef, $my_slow);
                exp_continue; } ],
        [ 'new password again:', sub { my $fh = shift;
                if ( $sent_password > 1 ) {
                  $changed_password = 0;
                } else {
                  print $fh "$res_password\n";
                  $sent_password++;
                  exp_continue;
                } } ],
        [ 'assword:', sub { my $fh = shift;
                if ( $sent_password > 1 ) {
                  $changed_password = 0;
                } else {
                  print $fh "$res_password\n";
                  $changed_password++;
                  exp_continue;
                } } ],
        [ 're-use', sub { $changed_password = 0;
                $self->pinfo($host, "Error in unlock, password previously used");
                } ],
        [ 'reuse', sub { $changed_password = 0;
                $self->pinfo($host, "Error in unlock, password previously used");
                } ],
        [ 'not found', sub { $changed_password = 0;
                $self->pinfo($host, "Error in unlock, cannot find passwd command");
                } ],
        [ 'Invalid login', sub { $changed_password = 0;
                $self->pinfo($host, "Error in unlock, $res_username does not exist");
                } ],
        [ 'does not', sub { $changed_password = 0;
                $self->pinfo($host, "Error in unlock, $res_username does not exist");
                } ],
        [ 'access protected', sub { $changed_password = 0;
                $self->pinfo($host, "Error in unlock, $res_username does not exist");
                } ],
        [ eof => sub { $changed_password = 0; } ],
        [ timeout => sub { $self->pinfo($host, "Error in unlock, timeout"); } ],
        '-re', $self->user_prompt,
    );
        
    $host_obj->shell->clear_accum();
    if ( $changed_password ) {
      if ( $os eq "AIX" ) {
        $host_obj->shell->send("/usr/bin/chsec -f /etc/security/passwd -s $res_username -a flags=''\n");
        select(undef,undef,undef,0.25);
        $host_obj->shell->expect(5, '-re', $self->user_prompt);
      }
    } else {
      return(0);
    }
 
  return(1);
}

sub useradd {
  my ($self, $host, $command) = @_;

  my $host_obj = $self->host($host);
  my $os = $host_obj->os();

  my ($username,$uid,$group,$comment,$home,$shell) = split(',', $command);

  $username =~ s/ //g;
  $uid =~ s/ //g;
  $group =~ s/ //g;
  $comment =~ s/^(\s\t)*//g;
  $comment =~ s/(\s\t)*$//g;
  $home =~ s/ //g;
  $shell =~ s/ //g;

  if ( ! $username ) {
    $self->pinfo($host, "Error in useradd, no username provided");
    return(0);
  }

  if ( ! $shell ) {
   # Try to determine shell automatically.
   #
    $shell = '/bin/ksh';	# Default, in case something messes up
    $host_obj->shell->send("echo \$SHELL\n");
    select(undef,undef,undef,0.25);
    $host_obj->shell->expect(5,
	[ 'ksh', sub { $shell = "/bin/ksh"; exp_continue; } ],
	[ 'bash', sub { $shell = "/usr/bin/bash"; exp_continue; } ],
	'-re', $self->user_prompt, );

    $host_obj->shell->clear_accum();
  }

  if ( ! $home ) {
   # Try to determine location of /home automatically.
   #
    $home = '/home';		# Default, in case something messes up
    $host_obj->shell->send("pwd\n");
    $host_obj->shell->expect(5,
	[ '^\/export\/home', sub { $home = "/export/home"; exp_continue; } ],
	[ '^\/home', sub { $home = "/home"; exp_continue; } ],
	'-re', $self->user_prompt, );

    $home = $home ."/". $username ;
    $host_obj->shell->clear_accum();
  }

  my $success = 0;
  if ( $os eq 'AIX' ) {
    my $useradd_cmnd = "mkuser ";
    if ( $uid ) { $useradd_cmnd .= " id=$uid"; }
    if ( $group ) { $useradd_cmnd .= " pgrp=$group"; }
    if ( $home ) { $useradd_cmnd .= " home=$home"; }
    if ( $comment ) { $useradd_cmnd .= " gecos=\"$comment\""; }

    $host_obj->shell->send("$useradd_cmnd $username && echo SUCCESS\n");
    $host_obj->shell->expect(5,
	[ '^SUCCESS', sub { $success = 1; } ],
	'-re', $self->user_prompt, );
    $host_obj->shell->clear_accum();

  } else {
    my $useradd_cmnd = "useradd ";
    if ( $uid ) { $useradd_cmnd .= " -u $uid"; }
    if ( $group ) { $useradd_cmnd .= " -g $group"; }
    if ( $home ) { $useradd_cmnd .= " -d $home -m "; }
    if ( $comment ) { $useradd_cmnd .= " -c \"$comment\""; }

    $host_obj->shell->send("$useradd_cmnd $username && echo SUCCESS\n");
    $host_obj->shell->expect(5,
	[ '^SUCCESS', sub { $success = 1; } ],
	'-re', $self->user_prompt, );
    $host_obj->shell->clear_accum();
  }

  $host_obj->shell->clear_accum();
  if($success){
    $self->pinfo($host, "User $username created");
  } else {
    if($os eq 'AIX') {
      $self->pinfo($host, "Failed to add $username, mkuser returned error");
    } else {
      $self->pinfo($host, "Failed to add $username, useradd returned error");
    }
  }

  return($success);
}


1;

__END__

=head1 NAME

Rover::Core - Core functions for Rover module

=head1 VERSION

3.00

=head1 SYNOPSIS

  # Load Rover module, Core functions included automotically
  use Rover;
  $r = new Rover;

  # Run commands on specific hosts
  $r->login();
  $r->execute("host1", "uptime");

  # Or add to a ruleset
  $ruleset->add("execute", "uptime");

  # Run multiline commands using send method
  $ruleset->add("send",    'for i in user1 user2 root ; do');
  $ruleset->add("send",    'last | grep $i | head -1');
  $ruleset->add("execute", 'done');

  # Get and send files
  $ruleset->add("get_file", "/etc/issue.net");
  $ruleset->add("put_file", "/etc/motd, /etc/motd");

  # Unlock a user's password
  $ruleset->add("unlock", "user, newpass");

  # Add a new user to the system
  $ruleset->add("useradd", "user");
  $ruleset->add("useradd", "user,,,New User,/home/user,/bin/ksh");

  # Change your own password
  $ruleset->add("passwd", "newpass");


=head1 DESCRIPTION

Rover::Core supplies the basic set of commands for rover.  All of these
are included by default when loading the Rover module.  They are local
to the Rover object and can be called as an object method.  The following
methods are included:

  execute     Execute a command and wait for the prompt
  send        Send a command, do not wait for the prompt
  put_file    Transfer a local file to the remote host
  get_file    Transfer a file from the remote host
  unlock      Unlock a users password, should be the root user
  useradd     Add a user to the system
  passwd      Change your personal account password

=head1 USAGE

=over 4

=item $r->execute(hostname, command)

Runs the I<command> on the I<hostname>.  The I<hostname> must already be defined
in the Rover object, and have been logged in.  The command is sent and the user
prompt is expected before returning.  If the prompt is not returned, or it times
out waiting for it to return, the command will return an error.  Otherwise, 1 is
returned.

See B<VARIABLES> section for further details.

=item $r->send(hostname, command)

Send the I<command> to the I<hostname>.  Nothing is expected in return.  The send
function sends the command, waits briefly, then clears the accumulated buffer on
the expect object and returns.

=item $r->get_file(hostname, "remote_file [, local_file]");

Get the I<remote_file> and copy it locally to I<local_file>.  The I<local_file> is
optional, the default value is to copy it to the CWD using the same name.  By
default the I<local_file> will be appended with the name of the I<hostname>.

See B<VARIABLES> section for further details.

=item $r->put_file(hostname, "local_file [, remote_file]");

Send the I<local_file> to I<hostname>:I<remote_file>.  The I<remote_file> is
optional, the default value is to copy it to the remote PWD using the same
name.

=item $r->unlock(hostname, "user, newpass");

Set the password for I<user> to I<newpass>.  This command is typically not allowed
for any user other then root.

On AIX systems, it will also set the security flags to null, i.e. it will not require
the user to change the password on next login.

=item $r->useradd(hostname, "user,uid,group,comment,homedir,shell");

Add a user to the system.  The only required field is username, if any other field
is not present, that portion of the useradd/mkuser command will be left out.  However,
leaving the home and shell parameters blank will prompt useradd() to determine their
values automatically.

The useradd() function will attempt determine the location of /home based on the
current users /home directory.  If this fails it will default to /home.  This
behavior can be overridden by explicitly specifying the full path to the new users
home directory.

Shell is acquired by the $SHELL environment variable on the remote system.  This
also can be overridden via specifying a shell.

  Example 1:
  $r->useradd("host1", "testusr");

  Example 2:
  $r->useradd("host1", "testusr,50000,users,Test User,/home/test,/bin/bash");


=item $r->passwd(hostname, "newpass");

Changes the password for the current user to I<newpass>.

=back

=head1 VARIABLES

=over 4

=item $Rover::Core::ftp_append_hostname

When using get_file, this variable determines whether or not to append the
hostname to the local file.  Default is 1 (yes), by setting it to 0 it will
not append the hostname.

=item $Rover::Core::command_timeout

How long to wait for the execute method to return the prompt after sending
the command.

=item @Rover::Core::FTP::methods

An array of methods to attempt for file transfers.  Default values are:
"sftp", "ftp", "rcp", in that order.  This is the order each method is
attempted, and all methods are tried by default.  Change this if you have
an different preferred order, or if you dont want all methods included.

=item %Rover::Core::FTP::method_ports

This is a hash of ports for each method.  This is used when determining
availability of each of the file transfer methods.

=item $Rover::Core::FTP::login_as_self

If this is set to 0, the username will be specified when attempting to transfer
a file.  If this is set to anything else, no user will be specified.  This
is relavent when using Rover as user A, but logging in remotly as user B.

=item $Rover::Core::FTP::login_timeout

Login timeout for gaining an FTP object.


