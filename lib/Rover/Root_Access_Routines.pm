#****************************************************************************
# Root Access Routines for rover
# By Bryan Bueter, 09/10/2004
#
# Description: This module is a set of routines that attempt to gain elevated
# privilages (root) on an already existing remote shell.
#
# 10/13/2004
#   bugfix: su expect loses its place sometimes when multiple passwords are
#           needed.
#   bugfix: su would fail if it tried to set the prompt more then once.
#
#****************************************************************************

package Rover::Root_Access_Routines;
use Exporter;

$Rover::Root_Access_Routines::VERSION = "1.00";

@Rover::Root_Access_Routines::ISA = qw( Exporter );
@Rover::Root_Access_Routines::EXPORT_OK = qw( get_root_by_su get_root_by_sudo );

BEGIN {
  $Rover::Root_Access_Routines::command_timeout = 3;
  $Rover::Root_Access_Routines::sudo_shell = '/bin/ksh';
  $Rover::Root_Access_Routines::su_login = 1;

  @Rover::root_shell_access_routines = qw( get_root_by_su get_root_by_sudo );

  Rover::register_module("Rover::Root_Access_Routines", qw(
	$Rover::Root_Access_Routines::command_timeout
	$Rover::Root_Access_Routines::sudo_shell
	$Rover::Root_Access_Routines::su_login
	@Rover::root_shell_access_routines ));
};

sub get_root_by_su {
  my $exp_obj = shift;
  my $hostname = shift;
  my $os = shift;

  Rover::pdebug("DEBUG: get_root_by_su: getting root for '$hostname'\n");
  $exp_obj->clear_accum();

 # First check to see if we are root or not
 #
  $exp_obj->send("id\n");
  select(undef, undef, undef, 0.25);
  
  my $bail = 0; # Bail if we timeout running id
  
  $exp_obj->expect($Rover::Root_Access_Routines::command_timeout,
	[ 'uid=0', sub { $got_root = 1; exp_continue; } ],
	[ timeout => sub { $bail = 1; } ],
	'-re', $Rover::user_prompt,
  );
  
  if ( $bail ) {
    Rover::info($hostname, "Error timeout out running id, server may be too busy");
    return(0);
  }
  if ( $got_root ) {
    Rover::pdebug("DEBUG: $hostname: get_root_by_su: already root, returning success\n");
    return(1);
  }

  my @root_credentials;
  if ( $Rover::root_password_hash{$hostname} ) { push(@root_credentials, $Rover::root_password_hash{$hostname}); }
  push (@root_credentials, @Rover::root_password_list);

 # Dont even try to su if we dont have any passwords
 #
  if ( ! @root_credentials ) {
    Rover::pwarn("$hostname\tWarning get_root_by_su, no root passwords available\n");
    return (0);
  }

  my $got_root = 0;

  foreach my $root_pass ( @root_credentials ) {
    $exp_obj->clear_accum();
    if ( $Rover::Root_Access_Routines::su_login ) {
      $exp_obj->send("su - \n");
    } else {
      $exp_obj->send("su \n");
    }
    select(undef, undef, undef, 0.25);

    my $changed_prompt = 0;
    $exp_obj->expect($Rover::Root_Access_Routines::command_timeout,
	[ 'assword:', sub { my $fh = shift;
		select(undef, undef, undef, 0.25);
		$fh->clear_accum();
		$fh->send("$root_pass\n");
		select(undef, undef, undef, 0.25);
		exp_continue; } ],
	[ timeout => sub { if ( ! $changed_prompt ) {
		  $changed_prompt = 1;
		  $exp_obj->send("PS1='$Rover::user_prompt_force'\n\n");
		  select(undef,undef,undef,0.25);
		  exp_continue;
		} else {
		  $got_root = 0;
		}} ],
	'-re', $Rover::user_prompt, );

    $exp_obj->clear_accum();
    $exp_obj->send("id\n");
    select(undef, undef, undef, 0.25);

    my $bail = 0;	# Bail if we timeout running id

    $exp_obj->expect($Rover::Root_Access_Routines::command_timeout,
	[ 'uid=0', sub { $got_root = 1; exp_continue; } ],
	[ timeout => sub { $bail = 1; } ],
	'-re', $Rover::user_prompt, );

    if ( $bail ) { return(0); }
    if ( $got_root ) { last; }
  }
  return($got_root);
}

sub get_root_by_sudo {
  my $exp_obj = shift;
  my $hostname = shift;
  my $os = shift;

  Rover::pdebug("DEBUG: $hostname: get_root_by_sudo: getting root\n");
  $exp_obj->clear_accum();

 # First check to see if we are root or not
 #
  $exp_obj->send("id\n");
  select(undef, undef, undef, 0.25);
  
  my $bail = 0; # Bail if we timeout running id
  
  $exp_obj->expect($Rover::Root_Access_Routines::command_timeout,
	[ 'uid=0', sub { $got_root = 1; exp_continue; } ],
	[ timeout => sub { $bail = 1; } ],
	'-re', $Rover::user_prompt,
  );
  
  if ( $bail ) {
    Rover::pinfo($hostname, "Error timed out running id, server may be too busy\n");
    return(0);
  }
  if ( $got_root ) {
    Rover::pdebug("DEBUG: $hostname: get_root_by_su: already root, returning success\n");
    return(1);
  }

  $exp_obj->send("sudo -k\n");
  select(undef, undef, undef, 0.25);

  $exp_obj->expect($Rover::Root_Access_Routines::command_timeout, '-re', $Rover::user_prompt);

  $exp_obj->send("sudo $Rover::Root_Access_Routines::sudo_shell\n");
  select(undef, undef, undef, 0.25);

  my $got_root = 1;
  my $changed_prompt = 0;
  my @user_credentials = @Rover::user_credentials;

  $exp_obj->expect($Rover::Root_Access_Routines::command_timeout,
	[ 'assword:', sub { my $pass = shift @user_credentials;
		if ( ! $pass ) {
		  $got_root = 0;
		}
		my $fh = shift;
		select(undef, undef, undef, 0.25);
		$fh->clear_accum();
		$fh->send("$pass\n");
		select(undef, undef, undef, 0.25);
		exp_continue; } ],
	[ 'incident', sub { $got_root = 0; } ],
	[ 'incorrect password', sub { $got_root = 0; } ],
	[ 'will be reported', sub { $got_root = 0; } ],
	[ 'sudoers', sub { $got_root = 0; } ],
	[ 'not allowed', sub { $got_root = 0; } ],
	[ 'Sorry', sub { $got_root = 0; } ],
	[ 'not found', sub { $got_root = 0; } ],
	[ timeout => sub { if ( ! $changed_prompt ) {
		  $changed_prompt = 1;
		  $exp_obj->send("PS1='$Rover::user_prompt_force'\n\n");
		  select(undef,undef,undef,0.25);
		  exp_continue;
		} else {
		  $got_root = 0;
		}} ],
	'-re', $Rover::user_prompt, );

  return($got_root);
}

1;
