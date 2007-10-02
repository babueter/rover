#***************************************************************************
# Rover Package: 07/17/2007
# Author:        Bryan Bueter
#
#***************************************************************************
package Rover;
require 5.8.0;

use Config;
use Expect;
use Carp;
use lib ("$ENV{HOME}/.rover/contrib");

use Rover::Shell_Routines;
use Rover::Host;
use Rover::Core;
use Rover::Ruleset;
use Rover::Password;

use threads;
use warnings;

use strict 'subs';
use strict 'vars';

sub new {
  my $class = shift;

  my %host_info;
  my %rulesets;
  my $self = {
	_user => $ENV{'USER'},
	_user_credentials => [( )],
	_user_prompt => '[>#\$] $',
	_user_prompt_force => '$ ',

	_host_info => \%host_info,
	_rulesets => \%rulesets,

	_login_methods => [qw( shell_by_ssh shell_by_telnet shell_by_rlogin )],
	_ftp_methods => [qw( sftp ftp rcp )],

	_login_timeout => 5,
	_max_threads => 4,

	_lastrun_num_hosts => 0,
	_lastrun_num_succeed => 0,
	_lastrun_failed_password => 0,
	_lastrun_failed_profile => 0,
	_lastrun_failed_network => 0,
	_lastrun_failed_ruleset => 0,
	_lastrun_failed_getroot => 0,
	_lastrun_failed_hosts => [( )],

	_logs_dir => "$ENV{HOME}/.rover/logs",
	_debug => 0,
  };

  return bless $self, $class;
}

#***************************************************************************
# Message and alert functions
#***************************************************************************
sub perror {
# Print rover error messages
#
  my $self = shift;
  my $message = shift;
  print STDERR $message;
}

sub pinfo {
# Print rover infor messages
#
  my $self = shift;
  my $hostname = shift;
  my $message = shift;

  chomp $message;
  print "$hostname:\t$message\n";;

}

sub pwarn {
# Print rover warning messages
#
  my $self = shift;
  my $message = shift;

  chomp $message;
  print "$message\n" if $self->debug > 0;
}

sub pdebug {
# Print rover debug messages
#
  my $self = shift;
  my $message = shift;

  chomp $message;
  print "$message\n" if $self->debug > 1;
}

#***************************************************************************
# Settings
#***************************************************************************
sub user {
  my ($self, $user) = @_;

  $self->{_user} = $user if defined($user);
  return $self->{_user};
}

sub user_credentials {
  my $self = shift;
  my @user_credentials = @_;

  $self->{_user_credentials} = \@user_credentials if @user_credentials;
  return @{$self->{_user_credentials}};
}

sub user_prompt {
  my ($self, $user_prompt) = @_;

  $self->{_user_prompt} = $user_prompt if $user_prompt;
  return $self->{_user_prompt};
}

sub user_prompt_force {
  my ($self, $user_prompt_force) = @_;

  $self->{_user_prompt_force} = $user_prompt_force if defined($user_prompt_force);
  return $self->{_user_prompt_force};
}

sub logs_dir {
  my ($self, $logs_dir) = @_;

  $self->{_logs_dir} = $logs_dir if defined($logs_dir);
  return $self->{_logs_dir};
}

sub login_methods {
  my $self = shift;
  my @login_methods = @_;

  $self->{_login_methods} = \@login_methods if @login_methods;
  return @{$self->{_login_methods}};
}

sub login_timeout {
  my ($self, $login_timeout) = @_;

  $self->{_login_timeout} = $login_timeout if defined($login_timeout);
  return $self->{_login_timeout};
}

sub max_threads {
  my ($self, $max_threads) = @_;

  $self->{_max_threads} = $max_threads if defined($max_threads);
  return $self->{_max_threads};
}

sub debug {
  my ($self, $debug) = @_;

  $self->{_debug} = $debug if defined($debug);
  return $self->{_debug};
}

#***************************************************************************
# Host routines
#***************************************************************************
sub add_host {
  my $self = shift;
  my @hosts = @_;

  my $host_count = 0;
  foreach my $host (@hosts) {
    if (! gethostbyname($host) ) {
      $self->perror("Error: Unable to resolve hostname/address: $host, server will not be included\n");
      next;
    }
    $self->pdebug("DEBUG:$host:\tCreating host object");

    if ( $self->host_info($host) ) {
      $self->pwarn("Warning: attempting to add duplicate host '$host'\n");
      next;
    }
    $self->host_info($host, new Rover::Host($host, "Unknown", $self->user(), $self->user_credentials()))
	or $self->perror("Error: Unable to create host object for $host\n");
    $host_count++ if $self->host_info($host);
  }

  return($host_count);
}

sub del_host {
  my $self = shift;
  my @hosts = @_;

  my $host_count = 0;
  foreach my $host (@hosts) {
    if ( ! defined($self->{_host_info}->{$host}) ) {
      $self->pwarn("Warning: delete host failed, '$host' doesnt exist\n");
      next;
    }
    delete $self->{_host_info}->{$host};
    $host_count++;
  }

  return($host_count);
}

sub host_info {
  my ($self, $host, $obj) = @_;

  return keys(%{$self->{_host_info}}) if ! $host;

 # Atempting to recall a host that was not added
 #
  if ( ! defined($self->{_host_info}->{$host}) && ! defined($obj)  ) {
    return 0;
  }

  $self->{_host_info}->{$host} = $obj if defined($obj);
  return $self->{_host_info}->{$host};
}

sub login {
  my $self = shift;
  my @hosts = @_;

  if ( ! @hosts ) {
    @hosts = keys %{$self->{_host_info}}
  }

  my $successful_login_count = 0;
  foreach my $host ( @hosts ) {
    my $host_info = $self->host_info($host);

    $self->pdebug("DEBUG: Getting shell for $host (". $host_info->hostname() .")\n");

    my @login_methods = $self->login_methods();
    @login_methods = $host_info->login_methods if $host_info->login_methods;

    foreach my $method ( @login_methods ) {
      $self->$method($host_info);
      last if $host_info->shell() > 0;
    }

    if ( $host_info->shell() <= 0 ) {
      $self->perror("Error: Unable to get shell for host $host\n");

    } else {
     # Determine OS type and store results
     #
      my $os_type = "";
      $host_info->shell->send("uname -a #UNAME\n");
      $host_info->shell->expect(4,
          [ 'HP-UX', sub { $os_type = 'HP-UX'; exp_continue; } ],
          [ 'AIX', sub { $os_type = 'AIX'; exp_continue; } ],
          [ 'SunOS', sub { $os_type = 'SunOS'; exp_continue; } ],
          [ 'hostfax', sub { $os_type = 'hostfax'; exp_continue; } ],
          [ 'not found', sub { $os_type = 'Unknown'; exp_continue; } ],
          [ 'syntax error', sub { $os_type = 'Unknown'; exp_continue; } ],
          [ 'BSD/OS', sub { $os_type = 'BSD/OS'; exp_continue; } ],
          [ 'C:', sub { $os_type = 'Windows';
                  # Send appropriate return because \n didn't work.
                  my $fh = shift;
                  select(undef, undef, undef, 0.25);
                  $fh->send("^M"); } ],
          [ 'Linux', sub { $os_type = 'Linux'; exp_continue; } ],
          [ timeout => sub { $self->perror($host_info->hostname .":\tError: uname -a timed out, server may be running too slow\n"); } ],
          '-re', $self->user_prompt, );
  
      $host_info->shell->clear_accum();

      $host_info->os($os_type);
      $self->pwarn($host_info->hostname .":\tWarning: unknown os type, running ALL and Unknown commands\n") if $os_type eq 'Unknown';
    }
    $successful_login_count++ if $host_info->shell() > 0;
  }

  return($successful_login_count);
}

#***************************************************************************
# Ruleset routines
#***************************************************************************
sub rulesets {
  my ($self, $ruleset) = @_;

  return keys( %{$self->{_ruleset}} ) if ! defined($ruleset);

  if ( ! defined($self->{_ruleset}->{$ruleset}) ) {
    $self->{_ruleset}->{$ruleset} = new Rover::Ruleset;
  }
  return( $self->{_ruleset}->{$ruleset} );
}

sub run_rulesets {
 # Subroutine to run a list of rulesets against all hosts.  We use threading
 # to process more then one host at a time.
 #
  my $self = shift;
  my @rulesets = @_;

  my @verified_rulesets = ();
  foreach my $ruleset (@rulesets) {
   # Verify all rulesets exist, run only those that do
   #
    if ( $self->rulesets($ruleset) ) {
      push(@verified_rulesets, $ruleset);
    } else {
      $self->pwarn("Ruleset '$ruleset' does not exist, excluding from the list\n");
    }
  }
  @rulesets = @verified_rulesets;

  if ( ! @rulesets ) {
    $self->perror("Error: No rulesets to run\n");
    return(0);
  }

  my $max_threads = $self->max_threads();
  my @thread_ids = ();

  my @hosts = $self->host_info();
  my @threaded_hosts = ();

  $self->clear_status();
  $self->{_lastrun_num_hosts} = @hosts;

 # Set up results array:
 #   0=num succeded, 1=failed ruleset, 2=failed getroot,
 #   3=failed network, 4=failed profile, 5=failed password
 #
  my @results = (0, 0, 0, 0, 0, 0);
  my @failed_hosts = ();

 # Build a list of of hosts and login first, then thread on top
 #
  while ( @hosts || @threaded_hosts ) {
    my $host = shift @hosts;
    my $result = $self->login($host);
    if ( $result > 0 ) {

     # Determine if we need an FTP object from our list of rulesets.  If we do,
     # setup the ftp object first because that portion is not thread safe
     #
      my $need_ftp = 0;
      foreach my $ruleset_name ( @rulesets ) {
        my $ruleset = $self->rulesets($ruleset_name);

        if ( grep( /^[gp][eu]t_file/, $ruleset->list()) ) {
          my $host_info = $self->host_info($host);
          my $ftp_method = Rover::Core::FTP::determine_ftp_method( $host_info, "setup" );
          $self->pdebug("DEBUG:\tSetting up FTP object for ". $host_info->hostname ." using $ftp_method\n");
          $result = &$ftp_method( $host_info );

          if ( $result > 0 ) { $host_info->ftp->log_file($self->logs_dir ."/$host.log.ftp"); }
          last;
        }
      }
      if ( $result > 0 ) {
        $self->pdebug("DEBUG:\tAdding $host to threaded list\n");
        push(@threaded_hosts, $host);
      }
    }

    if ( $result <= 0 ) {
      $results[$result-1]++;
      push(@failed_hosts, $host);
    }

   # Our list is maxed out, we can now run our ruleset(s) with threads
   #
    if ( @threaded_hosts == $max_threads || ! @hosts ) {
      $self->pdebug("DEBUG:\tThreading for hosts: @threaded_hosts\n");
      if ( ! @hosts ) { $max_threads = @threaded_hosts }

      for (my $t=0; $t<$max_threads; $t++) {
        my $host_info = $self->host_info($threaded_hosts[$t]);
        next if ! $host_info->shell();

        $self->pdebug("DEBUG:\t\tThreading host ". $host_info->hostname .", thead id $t\n");
        $thread_ids[$t] = threads->new("exec_thread", $self, $host_info, @rulesets);
      }

      for (my $t=0; $t<$max_threads; $t++) {
        $self->pdebug("DEBUG:\t\tJoining thread id $t\n");
        my $result = $thread_ids[$t]->join();
        if ( ! $result ) {
          $results[1]++;
          push(@{$self->{_lastrun_failed_hosts}}, $threaded_hosts[$t]);

          $self->pdebug("DEBUG:\tReturned bad status ($result) for thread id $t ($threaded_hosts[$t])\n");
        } else {
          $results[0]++;
        }
        undef $thread_ids[$t];	# Fix for perl < 5.8.8
      }
      @threaded_hosts = ();
    }
  }

  $self->{_lastrun_num_succeed} = $results[0];
  $self->{_lastrun_failed_password} = $results[5];
  $self->{_lastrun_failed_profile} = $results[4];
  $self->{_lastrun_failed_network} = $results[3];
  $self->{_lastrun_failed_ruleset} = $results[1];
  $self->{_lastrun_failed_getroot} = $results[2];
  $self->{_lastrun_failed_hosts} = \@failed_hosts;

  return($results[0]);
}

sub exec_thread {
  my $rover = shift;
  my $host_info = shift;
  my @rulesets = @_;

  my $result = 1;
  foreach my $ruleset ( @rulesets ) {
   # Run each ruleset making sure the os of the host matches the os_list of the ruleset
   #
    $rover->pdebug("DEBUG:\tRunning ruleset '$ruleset' on host '". $host_info->hostname ."'\n");
    my $ruleset_obj = $rover->rulesets($ruleset);

    my $host_os = $host_info->os;
    if ( $ruleset_obj->os_list() && ! grep( /^$host_os$/, $ruleset_obj->os_list() ) ) {
      $rover->pdebug("DEBUG:\t\tSkipping '$ruleset' for OS $host_os\n");
      next;
    }

    foreach my $ruleset_command ( $ruleset_obj->commands ) {
      $rover->pdebug("DEBUG:\t\tRunning ruleset command on '". $host_info->hostname ."': $ruleset_command\n");

      my $command = $ruleset_command->[0];
      my $args = $ruleset_command->[1];

      $result = $rover->$command($host_info, $args);
      last if ! $result;
    }
    last if ! $result;
  }

  if ( $result ) {
    $rover->pdebug("DEBUG:\t\tRuleset success, soft_closing object\n");
    $host_info->soft_close();

  } else {
    $rover->pdebug("DEBUG:\t\tRuleset failure ($result), hard_closing object\n");
    $host_info->hard_close();

  }
  return($result);
}

sub clear_status {
  my $self = shift;

  $self->{_lastrun_num_hosts} = 0;
  $self->{_lastrun_num_succeed} = 0;
  $self->{_lastrun_failed_password} = 0;
  $self->{_lastrun_failed_profile} = 0;
  $self->{_lastrun_failed_network} = 0;
  $self->{_lastrun_failed_ruleset} = 0;
  $self->{_lastrun_failed_getroot} = 0;
  $self->{_lastrun_failed_hosts} = [ ( ) ];

}

sub status {
  my $self = shift;

  my %results;
  my @failed_hosts = @{$self->{_lastrun_failed_hosts}};

  $results{num_hosts} = $self->{_lastrun_num_hosts};
  $results{num_succeed} = $self->{_lastrun_num_succeed};
  $results{failed_password} = $self->{_lastrun_failed_password};
  $results{failed_profile} = $self->{_lastrun_failed_profile};
  $results{failed_network} = $self->{_lastrun_failed_network};
  $results{failed_ruleset} = $self->{_lastrun_failed_ruleset};
  $results{failed_getroot} = $self->{_lastrun_failed_getroot};
  $results{failed_hosts} = \@failed_hosts;

  return(%results);
}

1;

__END__

=head1 NAME

Rover - Run arbitrary commands on remote servers using Expect for perl

=head1 VERSION

3.00

=head1 SYNOPSIS

  use Rover;

  my $r = new Rover;

  # Add hosts we want to execute remote commands on
  $r->add_hosts("host1", "host2", "host3");
  
  # Method #1, create a ruleset and run in parallel
  my $ruleset = $r->rulesets("Ruleset 1");
  $ruleset->add("execute", "uptime");
  $ruleset->add("execute", "who");
  $ruleset->add("get_file", "/etc/motd");
  $r->run_rulesets("Ruleset 1");

  # Method #2, login and run the commands in serial
  $r->login("host1");
  $r->execute( $r->host_info("host1"), "uptime");
  $r->execute( $r->host_info("host1"), "who");
  $r->get_file( $r->host_info("host1"), "/etc/motd");

  # Close the host objects when we are done (not needed for method 1)
  $r->host_info("host1")->soft_close();

  # Or avoid actually logging out and just kill the sessions
  $r->host_info("host1")->hard_close();

=head1 DESCRIPTION

The Rover module is a wrapper of the Expect for perl module.  It aids in
managing SSH, Telnet, Rlogin, and SFTP/FTP connections to remote hosts,
enabling you to execute commands, transfer files, add users, et al, without
having to manage the login process.

=head1 USAGE

=over 4

=item new Rover ()

Create a new Rover object.  You may want to change some defaults before
actually creating the object, see the VARIABLES section below

=item $r->add_host( @hosts )

Add a list of hosts to the rover section.  This creates a Rover::Host object
for each host in the list and makes them available via the $r->host_info
method.  The hosts in the array passed to this routine are either IP addresses
or host names that must resolve to an address.  That is also the identifier
used to recall the host object.

The return value for this function is the number of successfull hosts that
where added.

=item $r->del_host( @hosts )

Delete a host, or list of hosts from the rover config.  The return value is the
number of successfull hosts deleted from Rover.

=item $r->host_info( $hostname | undef )

Return the host object referenced by "hostname".  This is a reference to
the Rover::Host object used by Rover.  If no hostname is provided, an
array is returned with a list of the hostnames available.

=item $r->login( @hosts | undef )

Logs into each host specified in @hosts and sets up the Expect object.
The @hosts parameter is optional, the default action is to log into
all hosts stored in the Rover object.

This function is not threaded, and could take a long time to run for
more then 20 or so hosts.  If your using the $r->run_rulesets()
routine, you do not need to run this first.

=item $r->rulesets( $ruleset | undef )

Create and/or return a Rover::Ruleset object.  If the "ruleset" name
passed to the function does not exist, one is created.  The return
value is the Rover::Ruleset object.

=item $r->run_rulesets( @rulesets )

Run, in parallel, a list of Rulesets on all hosts stored in the Rover
object.  This process uses threading to login to each host, set up an
Expect object, execute each ruleset, and logout.

The number of concurrent threads is determined by $r->max_threads.

Results are stored within the Rover object.  They can be recalled using
the $r->status() routine.

=item $r->status()

Return the results of the previous $r->run_rulesets command.  This
returns a hash with the following keys:

  num_hosts       : The number of hosts attempted
  num_succeed     : The number of hosts that did not encounter an error
  failed_password : The number of failures due to incorrect password
  failed_profile  : The number of failures caused by Expect not matching a users prompt
  failed_network  : The number of hosts unreachable
  failed_ruleset  : The number of failures due ot ruleset failures
  failed_getroot  : The number of failures due to not being able to get root
  failed_hosts    : A reference to an array containing the names of the hosts that failed

=item $r->user( $username | undef )

Set or return the username to be used in the login process.  The default
value is $ENV{USER}.

=item $r->user_credentials( @passwords | undef )

Set or return the password list to be used in the login process.  By default
there is no value.

=item $r->user_prompt( $regex | undef )

Set or return the regular expression string that matches the user prompt
during the login process.  This is also used for ruleset functions to determine
when the command has returned.

The default value is '[>#\$] $', which should match most default system prompts,
including the root user.

=item $r->user_prompt_force( $prompt | undef )

Set or return the value used in setting the users prompt.  The login process
will attempt to set the prompt only when it detects a login success but times
out attempting to Expect the prompt.

The default value for this is '$ '.

=item $r->logs_dir( $dir | undef )

Set or return the directory where all the Expect logs are stored.  This defaults
to "$ENV{USER}/.rover/logs".

=item $r->login_timeout( $seconds | undef )

Set or return the timeout value used in the Expect block during login.  This defaults
to 5 seconds.

=item $r->max_threads( $count | undef )

Set or return the maximum number of threads to use in parallel.  The default is 4.

=item $r->debug( $debug | undef )

Set or return the debug level.  Values are 0 = Only fatal errors, 1 = Warnings and
informational messages, 2 = debuging output.  The default value is 0.


