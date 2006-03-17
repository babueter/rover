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

package User_Admin;
use Exporter;

our $VERSION = "1.00";

@User_Admin::ISA = qw( Exporter );
@User_Admin::EXPORT = qw( userlist grouplist useradd groupadd userdel groupdel unlock );
$User_Admin::timeout = 15;

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
        [ timeout => sub { print STDERR "$hostname:Error: command timed out, server may be running too slow\n"; } ],
        '-re', $Rover::user_prompt, );
        $exp_obj->clear_accum();
	if($success){
          print "$hostname:Success - User: $user, found\n" if $Rover::debug > 1;
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
          print "$hostname:\tFailed - User: $user, doesn\'t exist\n" if $Rover::debug > 1;
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
        [ timeout => sub { print STDERR "$hostname:Error: command timed out, server may be running too slow\n"; } ],
        '-re', $Rover::user_prompt, );
        $exp_obj->clear_accum();
        if($success){
          print "$hostname:Success - Group: $group, found\n" if $Rover::debug > 1;
          $exp_obj->clear_accum();
          $exp_obj->send("grep '^$group:' /etc/group | awk -F: '{print $awk_args}'\n");
          $exp_obj->expect(5, '-re', $Rover::user_prompt, );
          $exp_obj->clear_accum();
        } else {
          print "$hostname:Failed - Group: $group, doesn\'t exist\n" if $Rover::debug > 1;
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
    print "$hostname:\tError: uesradd: no username provided, cannot continue\n";
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
    [ '^0', sub { $success = 1; exp_continue; } ],
    [ '^1', sub { exp_continue; } ],
    [ timeout => sub { print STDERR "$hostname:Error: command timed out, server may be running too slow\n"; } ],
    '-re', $Rover::user_prompt, );
  $exp_obj->clear_accum();
  if($success){
    print "$hostname:\tSuccess - user $username has been created\n" if $Rover::debug > 1;
  } else {
    if($os eq 'AIX') {
      print "$hostname:\tFailed  - user $username was NOT added, mkuser\(\) returned an error... \n" if $Rover::debug > 1;
    } else {
      print "$hostname:\tFailed  - user $username was NOT added, useradd\(\) returned an error... \n" if $Rover::debug > 1;
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
    print "$hostname:\tError: groupadd: No group name specified, cannot continue\n";
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
    [ '^0', sub { $success = 1; exp_continue; } ],
    [ '^1', sub { exp_continue; } ],
    [ timeout => sub { print STDERR "$hostname:\tError: command timed out, server may be running too slow\n"; } ],
    '-re', $Rover::user_prompt, );
  $exp_obj->clear_accum();
  if($success){
    print "$hostname:\tSuccess - group $group has been created\n" if $Rover::debug > 1;
  } else {
    if($os eq 'AIX') {
      print "$hostname:\tFailed  - group $group was NOT added, mkgroup\(\) returned an error... \n" if $Rover::debug > 1;
    } else {
      print "$hostname:\tFailed  - group $group was NOT added, groupadd\(\) returned an error... \n" if $Rover::debug > 1;
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
    print "$hostname:\tError: userdel: No username specified, cannot continue\n";
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
    [ '^0', sub { $success = 1; exp_continue; } ],
    [ '^1', sub { exp_continue; } ],
    [ timeout => sub { print STDERR "$hostname:Error: command timed out, server may be running too slow\n"; } ],
    '-re', $Rover::user_prompt, );
  $exp_obj->clear_accum();
  if($success){
    print "$hostname:\tSuccess - user $user has been removed\n" if $Rover::debug > 1 ;
  } else {
    if($os eq 'AIX') {
      print "$hostname:\tFailed  - user $user was NOT removed, rmuser\(\) returned an error... \n" if $Rover::debug > 1 ;
    } else {
      print "$hostname:\tFailed  - user $user was NOT removed, userdel\(\) returned an error... \n" if $Rover::debug > 1 ;
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
    print "$hostname:\tError: groupdel: No group specified, cannot continue\n";
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

  $exp_obj->send("echo \$?\n");
  $exp_obj->expect(4,
    [ '^0', sub { $success = 1; exp_continue; } ],
    [ '^1', sub { exp_continue; } ],
    [ timeout => sub { print STDERR "$hostname:\tError: command timed out, server may be running too slow\n"; } ],
    '-re', $Rover::user_prompt, );
  $exp_obj->clear_accum();
  if($success){
    print "$hostname:\tSuccess - group $group has been removed\n" if $Rover::debug > 1 ;
  } else {
    if($os eq 'AIX') {
      print "$hostname:\tFailed  - group $group was NOT removed, rmgroup\(\) returned an error... \n" if $Rover::debug > 1;
    } else {
      print "$hostname:\tFailed  - group $group was NOT removed, groupdel\(\) returned an error... \n" if $Rover::debug > 1;
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
    print "$hostname:\tError: unlock: username cannot be NULL.\n";
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
                print "$hostname:\tError: unlock: Password previusly used\n" if $Rover::debug;
                } ],
        [ 'reuse', sub { $changed_password = 0;
                print "$hostname:\tError: unlock: Password previusly used\n" if $Rover::debug;
                } ],
        [ 'not found', sub { $changed_password = 0;
                print "$hostname:\tError: unlock: Can't find passwd command\n" if $Rover::debug;
                } ],
        [ 'Invalid login', sub { $changed_password = 0;
                print "$hostname:\tError: unlock: $res_username does not exist on the system\n" if $Rover::debug;
                } ],
        [ 'does not', sub { $changed_password = 0;
                print "$hostname:\tError: unlock: $res_username does not exist on the system\n" if $Rover::debug;
                } ],
        [ 'access protected', sub { $changed_password = 0;
                print "$hostname:\tError: unlock: $res_username does not exist on the system\n" if $Rover::debug;
                } ],
        [ eof => sub { $changed_password = 0; } ],
        [ timeout => sub { $changed_password = 0; } ],
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
