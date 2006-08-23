#****************************************************************************
# User_Admin for rover
# By: John Kellner, 09/16/2004
#
# Description: This module will provide common functions which will allow for
# cross platform user administration
#
# Functions contained are:
#
#	userlist()		grouplist()	unlock()
#	useradd()		groupadd()
#	userdel()		groupdel()
#
#****************************************************************************

package Rover::User_Admin;
use Exporter;

our $VERSION = "1.00";

@Rover::User_Admin::ISA = qw( Exporter );
@Rover::User_Admin::EXPORT = qw( userlist grouplist useradd groupadd userdel groupdel unlock );

BEGIN {
  $Rover::User_Admin::timeout = 15;

  Rover::register_module("Rover::User_Admin", qw( $Rover::User_Admin::timeout ) );
}

sub userlist {
  my $command = shift;
  my $exp_obj = shift;
  my $hostname = shift;
  my $os = shift;

  my $awk_args = "\$1";
  my $groups = 0;

  my ($list,$options,@trash) = split(':', $command);

  $awk_args .= "\":\"\$3" unless $options !~ /uid/;
  $awk_args .= "\":\"\$4" unless $options !~ /gid/;
  $awk_args .= "\":\"\$5" unless $options !~ /comment/;
  $awk_args .= "\":\"\$5" unless $options !~ /gecos/;
  $awk_args .= "\":\"\$6" unless $options !~ /home/;
  $awk_args .= "\":\"\$7" unless $options !~ /shell/;
  $groups=1 unless $options !~ /groups/;

  if($list eq 'ALL' || $list eq ''){
    $exp_obj->clear_accum();
    $exp_obj->send("awk -F: '{print $awk_args}' /etc/passwd\n");
    $exp_obj->expect(5, '-re', $Rover::user_prompt, );
    $exp_obj->clear_accum();
  } else {

    my @users = split(',', $list);

    for (@users){
      my $user = $_;
      my $success = 0;
      $exp_obj->clear_accum();
      $exp_obj->send("grep -c '^$user:' /etc/passwd\n");
      $exp_obj->expect(4,
        [ '^1', sub { $success = 1; exp_continue; } ],
        [ '^0', sub { exp_continue; } ],
        [ timeout => sub { Rover::pinfo($hostname, "Error in userlist, timeout"); } ],
        '-re', $Rover::user_prompt, );
        $exp_obj->clear_accum();
	if($success){
          $exp_obj->clear_accum();
          $exp_obj->send("grep '^$user:' /etc/passwd | awk -F: '{print $awk_args}'\n");
          $exp_obj->expect(4,
            '-re', $Rover::user_prompt, );
          $exp_obj->clear_accum();

          if( $groups ){
            $exp_obj->clear_accum();
            $exp_obj->send("groups $user\n");
            $exp_obj->expect(5, '-re', $Rover::user_prompt, );
            $exp_obj->clear_accum();
          }

        } else {
          Rover::pinfo($hostname, "Failed - User $user doesnt exist");
          return(0);
        }
    }
  }

  return(1);
}

sub grouplist {
  my $command = shift;
  my $exp_obj = shift;
  my $hostname = shift;
  my $os = shift;

  my ($list,$options,@trash) = split(':', $command);

  my $awk_args = "\$1";

  $awk_args .= "\":\"\$3" unless $options !~ /gid/;
  $awk_args .= "\":\"\$4" unless $options !~ /members/;
  $awk_args .= "\":\"\$4" unless $options !~ /users/;

  if($list eq 'ALL' || $list eq ''){
    $exp_obj->clear_accum();
    $exp_obj->send("awk -F: '{print $awk_args}' /etc/group\n");
    $exp_obj->expect(5, '-re', $Rover::user_prompt, );
    $exp_obj->clear_accum();
  } else {
    my @groups = split(',', $list);
    for (@groups){

      my $group = $_;
      my $success = 0;

      $exp_obj->clear_accum();
      $exp_obj->send("grep -c '^$group:' /etc/group\n");
      $exp_obj->expect(4,
        [ '^1', sub { $success = 1; exp_continue; } ],
        [ '^0', sub { exp_continue; } ],
        [ timeout => sub { Rover::pinfo($hostname, "Error in grouplist, timeout"); } ],
        '-re', $Rover::user_prompt, );
        $exp_obj->clear_accum();
        if($success){
          Rover::pinfo($hostname, "Group $group exists");
          $exp_obj->clear_accum();
          $exp_obj->send("grep '^$group:' /etc/group | awk -F: '{print $awk_args}'\n");
          $exp_obj->expect(5, '-re', $Rover::user_prompt, );
          $exp_obj->clear_accum();
        } else {
          Rover::pinfo($hostname, "Failed - Group $group doesnt exist");
          return(0);
        }
    }
  }
                                                                                                                                                                            
  return(1);
}

sub useradd {
  my $command = shift;
  my $exp_obj = shift;
  my $hostname = shift;
  my $os = shift;

  my ($username,$uid,$group,$comment,$home,$shell) = split(',', $command);

  $username =~ s/ //g;
  $uid =~ s/ //g;
  $group =~ s/ //g;
  $comment =~ s/^(\s\t)*//g;
  $comment =~ s/(\s\t)*$//g;
  $home =~ s/ //g;
  $shell =~ s/ //g;

  if ( ! $username ) {
    Rover::pinfo($hostname, "Error in useradd, no username provided");
    return(0);
  }

  if ( ! $shell ) {
   # Try to determine shell automatically.
   #
    $shell = '/bin/ksh';	# Default, in case something messes up
    $exp_obj->send("echo \$SHELL\n");
    select(undef,undef,undef,0.25);
    $exp_obj->expect(5,
	[ 'ksh', sub { $shell = "/bin/ksh"; exp_continue; } ],
	[ 'bash', sub { $shell = "/usr/bin/bash"; exp_continue; } ],
	'-re', $Rover::user_prompt, );

    $exp_obj->clear_accum();
  }

  if ( ! $home ) {
   # Try to determine location of /home automatically.
   #
    $home = '/home';		# Default, in case something messes up
    $exp_obj->send("pwd\n");
    $exp_obj->expect(5,
	[ '^\/export\/home', sub { $home = "/export/home"; exp_continue; } ],
	[ '^\/home', sub { $home = "/home"; exp_continue; } ],
	'-re', $Rover::user_prompt, );

    $home = $home ."/". $username ;
    $exp_obj->clear_accum();
  }

  my $success = 0;
  if ( $os eq 'AIX' ) {
    my $useradd_cmnd = "mkuser ";
    if ( $uid ) { $useradd_cmnd .= " id=$uid"; }
    if ( $group ) { $useradd_cmnd .= " pgrp=$group"; }
    if ( $home ) { $useradd_cmnd .= " home=$home"; }
    if ( $comment ) { $useradd_cmnd .= " gecos=\"$comment\""; }

    $exp_obj->send("$useradd_cmnd $username\n");
    $exp_obj->expect(5, '-re', $Rover::user_prompt, );
    $exp_obj->clear_accum();

  } else {
    my $useradd_cmnd = "useradd ";
    if ( $uid ) { $useradd_cmnd .= " -u $uid"; }
    if ( $group ) { $useradd_cmnd .= " -g $group"; }
    if ( $home ) { $useradd_cmnd .= " -d $home -m "; }
    if ( $comment ) { $useradd_cmnd .= " -c \"$comment\""; }

    $exp_obj->send("$useradd_cmnd $username\n");
    $exp_obj->expect(5, '-re', $Rover::user_prompt, );
    $exp_obj->clear_accum();
  }

  $exp_obj->clear_accum();
  $exp_obj->send("echo \$?\n");
  $exp_obj->expect(4,
    [ '^0$', sub { $success = 1; exp_continue; } ],
    [ '^[1-9]', sub { exp_continue; } ],
    [ timeout => sub { Rover::pinfo($hostname, "Error in useradd, timeout"); } ],
    '-re', $Rover::user_prompt, );

  $exp_obj->clear_accum();
  if($success){
    Rover::pinfo($hostname, "User $username created");
  } else {
    if($os eq 'AIX') {
      Rover::pinfo($hostname, "Failed to add $username, mkuser returned error");
    } else {
      Rover::pinfo($hostname, "Failed to add $username, useradd returned error");
    }
  }

  return($success);
}

sub groupadd {
  my $command = shift;
  my $exp_obj = shift;
  my $hostname = shift;
  my $os = shift;

  my ($group,$gid) = split(',', $command);
  $gid =~ s/ //g;

  if ( ! $group ) {
    Rover::pinfo($hostname, "Error in groupadd, no group specified");
    return(0);
  }

  my $success = 0;

  $exp_obj->clear_accum();
  if ( $os eq 'AIX' ) {
    my $groupadd_cmnd = "mkgroup ";
    if ( $gid ) { $groupadd_cmnd .= " id=$gid"; }

    $exp_obj->send("$groupadd_cmnd $group\n");
    $exp_obj->expect(5, '-re', $Rover::user_prompt, );
  } else {
    my $groupadd_cmnd = "groupadd ";
    if ( $gid ) { $groupadd_cmnd .= " -g $gid"; }

    $exp_obj->send("$groupadd_cmnd $group\n");
    $exp_obj->expect(5, '-re', $Rover::user_prompt, );
  }

  $exp_obj->clear_accum();
  $exp_obj->send("echo \$?\n");
  $exp_obj->expect(4,
    [ '^0$', sub { $success = 1; exp_continue; } ],
    [ '^[1-9]', sub { exp_continue; } ],
    [ timeout => sub { Rover::pinfo($hostname, "Error in groupadd, timeout"); } ],
    '-re', $Rover::user_prompt, );

  $exp_obj->clear_accum();
  if($success){
    Rover::pinfo($hostname, "Group $group created");
  } else {
    if($os eq 'AIX') {
      Rover::pinfo($hostname, "Failed to add $group, mkuser returned error");
    } else {
      Rover::pinfo($hostname, "Failed to add $group, groupadd returned error");
    }
  }

  return($success);
}

sub userdel {
  my $command = shift;
  my $exp_obj = shift;
  my $hostname = shift;
  my $os = shift;

  my ($username) = split(',', $command);

  if ( ! $username ) {
    Rover::pinfo($hostname, "Error in userdel, no username specified");
    return(0);
  }

  my $success = 0;

  $exp_obj->clear_accum();
  if ( $os eq 'AIX' ) {
    $exp_obj->send("rmuser $username\n");
    $exp_obj->expect(5, '-re', $Rover::user_prompt, );
  } else {
    $exp_obj->send("userdel $username\n");
    $exp_obj->expect(5, '-re', $Rover::user_prompt, );
  }

  $exp_obj->clear_accum();
  $exp_obj->send("echo \$?\n");
  $exp_obj->expect(4,
    [ '^0$', sub { $success = 1; exp_continue; } ],
    [ '^[1-9]', sub { exp_continue; } ],
    [ timeout => sub { Rover::pinfo($hostname, "Error in userdel, timeout"); } ],
    '-re', $Rover::user_prompt, );

  $exp_obj->clear_accum();
  if($success){
    Rover::pinfo($hostname, "User $username has been removed");
  } else {
    if($os eq 'AIX') {
      Rover::pinfo($hostname, "Failed to remove $username, rmuser returned error");
    } else {
      Rover::pinfo($hostname, "Failed to remove $username, userdel returned error");
    }
  }

  return($success);
}

sub groupdel {
  my $command = shift;
  my $exp_obj = shift;
  my $hostname = shift;
  my $os = shift;

  my ($group) = split(',', $command);

  if ( ! $group ) {
    Rover::pinfo($hostname, "Error in groupdel, no group specified");
    return(0);
  }

  my $success = 0;

  $exp_obj->clear_accum();
  if ( $os eq 'AIX' ) {
    $exp_obj->send("rmgroup $group\n");
    $exp_obj->expect(5, '-re', $Rover::user_prompt, );
  } else {
    $exp_obj->send("groupdel $group\n");
    $exp_obj->expect(5, '-re', $Rover::user_prompt, );
  }

  select(undef,undef,undef,0.25);
  $exp_obj->clear_accum();

  $exp_obj->send("echo \$?\n");
  $exp_obj->expect(4,
    [ '^0$', sub { $success = 1; exp_continue; } ],
    [ '^[1-9]', sub { exp_continue; } ],
    [ timeout => sub { Rover::pinfo($hostname, "Error in groupdel, timeout"); } ],
    '-re', $Rover::user_prompt, );

  $exp_obj->clear_accum();
  if($success){
    Rover::pinfo($hostname, "Group $group has been removed");
  } else {
    if($os eq 'AIX') {
      Rover::pinfo($hostname, "Failed to remove $group, rmgroup returned error");
    } else {
      Rover::pinfo($hostname, "Failed to remove $group, groupdel returned error");
    }
  }

  return($success);
}

sub unlock {
  my $command = shift;
  my $exp_obj = shift;
  my $hostname = shift;
  my $os = shift;
                                                                                                                                               
  my ($res_username, $res_password) = split(/\,/, $command, 2);
  $res_username =~ s/ //g;
  $res_password =~ s/ //g;
                                                                                                                                               
  if ( $res_username eq '' ) {
    Rover::pinfo($hostname, "Error in unlock, no username specified");
    return(0);
  }
                                                                                                                                               
   # OS specific unlock commands
   #
    if ( $os eq "HP_UX") {
        $exp_obj->send("/usr/lbin/modprpw -k $res_username\n");
        select(undef,undef,undef,0.25);
        $exp_obj->expect(5, '-re', $Rover::user_prompt);
    } elsif ( $os eq "AIX" ) {
        $exp_obj->send("/usr/bin/chsec -f /etc/security/lastlog -a \"unsuccessful_login_count=0\" -s $res_username\n");
        select(undef,undef,undef,0.25);
        $exp_obj->expect(5, '-re', $Rover::user_prompt);
        
        $exp_obj->send("/usr/bin/chuser account_locked='false' login='true' $res_username\n");
        select(undef,undef,undef,0.25);
        $exp_obj->expect(5, '-re', $Rover::user_prompt);
    }
        
    my $changed_password = 0;
    $exp_obj->send("passwd $res_username\n");
    select(undef,undef,undef,0.25);
 
    my $sent_password = 0;
    $exp_obj->expect(7,
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
                Rover::pinfo($hostname, "Error in unlock, password previously used");
                } ],
        [ 'reuse', sub { $changed_password = 0;
                Rover::pinfo($hostname, "Error in unlock, password previously used");
                } ],
        [ 'not found', sub { $changed_password = 0;
                Rover::pinfo($hostname, "Error in unlock, cannot find passwd command");
                } ],
        [ 'Invalid login', sub { $changed_password = 0;
                Rover::pinfo($hostname, "Error in unlock, $res_username does not exist");
                } ],
        [ 'does not', sub { $changed_password = 0;
                Rover::pinfo($hostname, "Error in unlock, $res_username does not exist");
                } ],
        [ 'access protected', sub { $changed_password = 0;
                Rover::pinfo($hostname, "Error in unlock, $res_username does not exist");
                } ],
        [ eof => sub { $changed_password = 0; } ],
        [ timeout => sub { Rover::pinfo($hostname, "Error in unlock, timeout"); } ],
        '-re', $Rover::user_prompt,
    );
        
    $exp_obj->clear_accum();
    if ( $changed_password ) {
      if ( $os eq "AIX" ) {
        $exp_obj->send("/usr/bin/chsec -f /etc/security/passwd -s $res_username -a flags=''\n");
        select(undef,undef,undef,0.25);
        $exp_obj->expect(5, '-re', $Rover::user_prompt);
      }
    } else {
      return(0);
    }
 
  return(1);
}

1;
__END__

=head1 NAME

Rover::User_Admin - User Administration module for Rover

=head1 VERSION

1.00

=head1 SYNOPSYS

  # Format for commands.run
  GENERAL:{
    ...

    # Add module to rover runtime environment
    use Rover::User_Admin;
  };

  Ruleset:{
    ...

    # List ALL users on a server
    userlist(ALL);

  };

The public functions available are as follows:

  Rover::User_Admin::userlist();
  Rover::User_Admin::grouplist();
  Rover::User_Admin::useradd();
  Rover::User_Admin::groupadd();
  Rover::User_Admin::userdel();
  Rover::User_Admin::groupdel();
  Rover::User_Admin::unlock();

=head1 DESCRIPTION

  The purpose of this module is to provide a platform independent set of functions
  around basic user management. It is not intended to provide an equivalent switch
  for all supported variants of user commands per platform.

  The basic use of this module is to include it in the Rover commands.run
  file in the GENERAL section (use Rover::User_Admin) and then call a public function
  in any defined ruleset. The Perl module file itself must exist in the modules
  directory, or anywhere within the @INC() path.

=head1 USAGE

=over 4

=item userlist();

  # List all accounts
  userlist(ALL);
   or with a subset, or all options
  userlist(ALL:uid,gid,comment,home,shell,groups);
  
  # List selective accounts
  userlist(root,nobody);
   or with a subset, or all options
  userlist(root,nobody:uid,gid,comment,home,shell,groups);

  One or more users can be provided separated by comma's. And one or more
  options can be provided sperated by comma's. The users and options are separated by
  a colon ':'. The only required item is the username, specifying additional options
  such as gid or comment will cause the output in the log file to contain only those
  fields of the /etc/passwd file. So the following command would provide output similar
  to:

  userlist(nobody:shell);
  
  Output in logfile
  nobody:/sbin/nologin

=item grouplist();

  # List all groups
  grouplist(ALL);
   or with a subset, or all options
  grouplist(ALL:gid,members);

  # List selective groups
  grouplist(bin,nobody);
   or with a subset, or all options
  grouplist(bin,nobody:gid,members);

  One or more groups can be provided separated by comma's. And one or more
  options can be provided separated by comma's. The groups and options are separated by
  a colon ':'. The only required item is the group name, specifying additional options
  such as gid or members will cause the output in the log file to contain only those
  fields of the /etc/group file. So the following command would provide output similar
  to:

  grouplist(nobody:gid);

  Output in logfile
  nobody:99

=item useradd();

  useradd(username,uid,group,comment,home,shell);

  The only required field is username, if any other field is not present, that portion
  of the useradd/mkuser command will be left out.  However, leaving the home and shell
  parameters blank will prompt useradd() to determine their values automatically. See
  below.

  The useradd() function will attempt to determine the location of /home based on the
  current users /home directory.  If this fails it will default to /home.  This
  behavior can be overridden by explicitly specifying the full path to the new users
  home directory.

  Shell is acquired by the $SHELL environment variable on the remote system.  This
  also can be overridden via specifying a shell.

  Example 1:
  useradd(test,50000,users,Test User,/home/test,/bin/bash);

  Example 2:
  useradd(test,,,Test User,,);

=item groupadd();

  groupadd(groupname,gid);

  Group name is required; gid is optional and will be left out of the groupadd/mkgroup
  commands if not specified.

  Example:
  groupadd(test,50000);

=item userdel();

  userdel(username);

  Example:
  userdel(test);

=item groupdel();

  groupdel(group);

  Example:
  groupdel(test);

=item unlock();

  unlock(username, password);

  This will set the password for a user specified.  If the system is an
  AIX server, it will also set the security flags to null, i.e. it will
  not require the user to change the password on next login.

  Example:
  unlock(test, temp123);

=head1 AUTHORS

John Kellner (jpkellner25@users.sourceforge.net)

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
