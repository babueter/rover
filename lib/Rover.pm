#***************************************************************************
# Rover package: 08/05/2004
# Last modified by: BAB
#
# WARNING: Do not modify this file, read the documentation and learn how to
# use the ~/.rover/config.run file to configure what you need, or use rovergtk.
#
#****************************************************************************
package Rover;

require 5.8.0;

use POSIX qw(:sys_wait_h _exit setsid);
use Fcntl qw(:DEFAULT :flock);
use File::Temp qw( :POSIX );

use IPC::SysV qw(IPC_PRIVATE S_IRWXU);
use IPC::Msg;

use Config;
use Expect;
use Carp;
use lib ("$ENV{HOME}/.rover/contrib");

if ( $Config{useithreads} ) {
  require threads;
}

use Exporter;

our $VERSION = '2.02';
our $AUTHORS = 'Bryan A. Bueter, Erik McLaughlin, Jayson A. Robinson';

@Rover::ISA = qw( Exporter );
@Rover::EXPORT = qw( load_config load_hosts clear_config save_config process_hosts );

use strict 'vars';
use strict 'subs';
use Expect;

sub clear_counters {
 # Reporting statistics
  @Rover::report_failed_hosts = ();
  $Rover::report_failed_profile = 0;
  $Rover::report_failed_password = 0;
  $Rover::report_failed_network = 0;
  $Rover::report_failed_root = 0;
  $Rover::report_failed_runrules = 0;

  $Rover::parent_id = $$;
  $Rover::global_process_count = 0;
  @Rover::global_process_completed_hosts = ();
  %Rover::global_process_current_host = ();
  %Rover::global_process_current_status = ();
}

sub clear_config {
 # General Rover configuration variables
  $Rover::user = $ENV{"USER"};
  @Rover::user_credentials = ();
  $Rover::user_prompt = '[>#\$] $';
  $Rover::user_prompt_force = '$ ';

 # Rover internals
  $Rover::debug = 0;
  $Rover::expert_mode = 0;
  %Rover::rulesets = ();
  $Rover::use_threads = 0;
  $Rover::parallel_process_count = 4;
  $Rover::external_watcher = 0;

 # Host information
  @Rover::hosts_list = ();
  %Rover::hosts_data = ();

 # File locations
  $Rover::config_file = $ENV{'HOME'} ."/.rover/config.run";
  $Rover::hosts_file = $ENV{'HOME'} ."/.rover/hosts.txt";
  $Rover::logs_dir = $ENV{'HOME'} ."/.rover/logs";

  $Rover::ipc_msg = undef;

  @Rover::AIX = ();
  @Rover::SunOS = ();
  @Rover::HP_UX = ();
  @Rover::FreeBSD = ();
  @Rover::OpenBSD = ();
  @Rover::Windows = ();
  @Rover::Linux = ();
  @Rover::UNKNOWN = ();
  @Rover::ALL = ();

 # Registered module variables
  %Rover::registered_modules = ();
  %Rover::registered_vars = ();

 # Global routines arrays
  @Rover::shell_access_routines = ();
  @Rover::root_shell_access_routines = ();
  @Rover::root_password_storage_routines = ();

 # Root password objects
  $Rover::root_access_required = 0;
  %Rover::root_password_hash = ();
  @Rover::root_password_list = ();

 # Set some expect values
  $Expect::Debug = 0;
  $Expect::Log_Stdout = 0;
}

BEGIN {
  our (
   # General Rover configuration variables
    $user,
    @user_credentials,
    $user_prompt,
    $user_prompt_force,

   # Rover internals
    $debug,
    $expert_mode,
    %rulesets,
    $use_threads,
    $parallel_process_count,
    $external_watcher,

   # Host information
    @hosts_list,
    %hosts_data,

   # File locations
    $config_file,
    $hosts_file,
    $logs_dir,
    $ipc_msg,

   # Arrays to store rulesets by platform.  Platform names should have
   # hyphins(-) converted to underscores(_).
    @OS_TYPES,
    @AIX,
    @SunOS,
    @HP_UX,
    @FreeBSD,
    @OpenBSD,
    @Windows,
    @Linux,
    @UNKNOWN,
    @ALL,

   # Registered module variables
    %registered_modules,
    %registered_vars,

   # Global routines arrays
    @shell_access_routines,
    @root_shell_access_routines,
    @root_password_storage_routines,

   # Root password objects
    $root_access_required,
    %root_password_hash,
    @root_password_list,

   # Reporting statistics
    @report_failed_hosts,
    $report_failed_profile,
    $report_failed_password,
    $report_failed_network,
    $report_failed_root,
    $report_failed_runrules,

    $parent_id,
    $global_process_count,
    @global_process_completed_hosts,
    %global_process_current_host,
    %global_process_current_status
  );

  @Rover::config_vars = qw(
	$Rover::user
	$Rover::user_prompt
	$Rover::user_prompt_force
	$Rover::root_access_required
	$Rover::debug
	$Rover::use_threads
	@Rover::shell_access_routines
	@Rover::root_shell_access_routines
	@Rover::root_password_storage_routines
	$Rover::parallel_process_count
	$Rover::expert_mode
	$Rover::config_file
	$Rover::hosts_file
	$Rover::logs_dir
	$Expect::Debug
	$Expect::Log_Stdout
  );

  @Rover::OS_TYPES = ('ALL', 'UNKNOWN', 'Linux', 'AIX', 'SunOS', 'HP_UX', 'FreeBSD', 'OpenBSD', 'Windows');

  $Rover::msqid_ds_field = 5;
  $Rover::exp_obj = undef;

  clear_config();
  clear_counters();
}

sub perror {
# Print rover error messages
#
  my $message = shift;
  print STDERR $message;
}

sub pinfo {
# Print rover infor messages
#
  my $hostname = shift;
  my $message = shift;

  if ( $Rover::parent_id == $$ ) {
    print "$hostname:\t$message\n";;
  } else {
    ipc_watcher_report($hostname, 255, $message);
  }

}

sub pwarn {
# Print rover warning messages
#
  my $message = shift;
  print $message if $Rover::debug > 0;
}

sub pdebug {
# Print rover debug messages
#
  my $message = shift;
  print $message if $Rover::debug > 1;
}

sub save_config {

  open (CONFIG_FILE, "> $Rover::config_file") or croak "Error: Cannot open config file for writing: '$Rover::config_file'\n";

  foreach my $os (@Rover::OS_TYPES) {
    my $tmp_name = "Rover::$os";
    if ( @{$tmp_name} ) {
      my $os_rules = "";
      foreach ( @{$tmp_name} ) {
        $os_rules .= "$_,";
      }
      chop($os_rules);
      print CONFIG_FILE "$os:$os_rules;\n\n";
    }
  };

  foreach my $ruleset (keys %Rover::rulesets) {
    print CONFIG_FILE "$ruleset:{\n";
    foreach my $line ( @{$Rover::rulesets{$ruleset}}) {
      print CONFIG_FILE "\t$line\n";
    }
    print CONFIG_FILE "};\n\n";
  }

  print CONFIG_FILE "GENERAL:{\n";
  foreach my $config_var ( @Rover::config_vars ) {
    my $var_name = $config_var;
    $var_name =~ s/^.// ;
    if ( $config_var =~ m/^\@/ ) {
      print CONFIG_FILE "\t$config_var = (";
      my $array_values = "";
      foreach my $value (@$var_name) {
        $array_values .= "\"$value\", ";
      }
      chop $array_values;
      chop $array_values;
      print CONFIG_FILE " $array_values);\n";
    } else {
      print CONFIG_FILE "\t$config_var = '". $$var_name ."' ;\n";
    }
  }
  print CONFIG_FILE "\n";

  foreach my $module ( keys %Rover::registered_modules ) {
   # What the heck, we'll just import everything we can
   #
    my $module_export = $module ."::EXPORT";
    my $module_export_ok = $module ."::EXPORT_OK";
    print CONFIG_FILE "\tuse $module qw(@$module_export @$module_export_ok );\n";

    foreach my $module_var ( @{ $Rover::registered_vars{ $module } } ) {
      if ( $module_var =~ m/^\$/ ) {
        my $module_var_name = $module_var;
        $module_var_name =~ s/^.// ;
        print CONFIG_FILE "\t$module_var = '". $$module_var_name ."' ;\n";
      }
    }
    print CONFIG_FILE "\n";
  }

  print CONFIG_FILE "};\n\n";

  close(CONFIG_FILE);
}

sub load_config {

  if ( ! -d "$ENV{'HOME'}/.rover" ) {
    mkdir "$ENV{'HOME'}/.rover" or die "Could not make rover config directory: $ENV{'HOME'}/.rover\n";
  }

  if ( ! -d "$ENV{'HOME'}/.rover/contrib" ) {
    mkdir "$ENV{'HOME'}/.rover/contrib" or die "Could not make rover contrib directory: $ENV{'HOME'}/.rover/contrib\n";
  }

  if ( ! -f "$Rover::config_file" ) {
    open(CONFIG_FILE, "> $Rover::config_file") or die "Could not open config file: $Rover::config_file\n";

    print CONFIG_FILE 'GENERAL:{
	use Rover::Shell_Access_Routines qw( shell_by_ssh shell_by_telnet shell_by_rlogin );
	use Rover::Root_Access_Routines qw( get_root_by_su get_root_by_sudo );
	use Rover::Run_Commands;
	use Rover::File_Transfer;
	use Rover::User_Admin;
	use Rover::Password;
};
';
    close(CONFIG_FILE);
  }

  if ( ! -d "$Rover::logs_dir" ) {
    mkdir $Rover::logs_dir or die "Could not make rover logs directroy: $Rover::logs_dir\n";
  }

  my $current_rule = "";
  my $current_rule_array = 0;
  my $inrule = 0;
  my $count = 0;
  my $instance = 0;

  open(CONFIG_FILE,$Rover::config_file) or die "Could not open config file: $Rover::config_file\n";
  while (<CONFIG_FILE>) {
    if ( m/^([\s\t]*)\#/ ) {next;}
    chomp $_;

   # Beginning of the line starts with a alpha and ends in anything.
    if ($_=~/(^[a-zA-Z0-9\s{}]+)(.*)$/) {

     # Reading OS section
      if ($_=~/(.*)(\w+)(:)([\w,]+)(;+)(\s*)$/) {
        my ($os,$rulename) = split(/\:/,$_,2);
        $os =~ s/-/_/g;
        $rulename =~ s/\;//;
        my @rulenames = split(",",$rulename);

        my $tmp_name = "Rover::$os";
        foreach my $tmp_rule ( @rulenames ) {
          Rover::pdebug "DEBUG: Pushing ruleset '$tmp_rule' to OS '$os'\n";
          push(@{$tmp_name}, $tmp_rule);
        }
      } #end OS section

     # rule definition
      if ($inrule) {
        if ( m/^([\s\t])*};([\s\t])*$/ ) {
          $inrule = 0;

          if ( $current_rule ne "GENERAL" ) {
            $Rover::rulesets{$current_rule} = $current_rule_array ;
          }
          $current_rule = "";
          next;
        }
        $_ =~ s/^[\s\t]//;

        if ( $current_rule eq "GENERAL" ) {
          Rover::pdebug "DEBUG: Setting general rule: $_\n";
          eval $_ ;
          croak "Error in '$Rover::config_file': $@" if $@;
          next;
        }

        Rover::pdebug "DEBUG: Pushing command for rule '$current_rule': '$_'\n";
        push (@{$current_rule_array}, $_);
      } #end rule definition

     # ruleset definition
      if ( m/^(.+):{[\s\t]*$/ ) {
        $current_rule = $1;
        $inrule = 1;

        my @new_array = ();
        $current_rule_array = \@new_array;
      } #end ruleset definition

    } #end if
  }
  close(CONFIG_FILE);

  return(1);
}

sub load_hosts {
  if (! stat($Rover::hosts_file) ) {
    system("touch $Rover::hosts_file");
  }

  open(HOSTS_FILE,$Rover::hosts_file);
  my $host_count = 1;
  Rover::pdebug "Reading in Hosts File ...\n";
  while (<HOSTS_FILE>) {
    chomp $_;

    my @host_list = split(/,/, $_ );
    my $host_name = shift @host_list ;

    if (! gethostbyname($host_name) ) {
      Rover::perror "Error: Unable to resolve hostname/address: $host_name, server will not be included\n";
      next;
    }
    Rover::pdebug "  $host_count.\t$host_name\n";
    $host_count++;
    push(@Rover::hosts_list, $host_name);
    $Rover::hosts_data{$host_name} = \@host_list ;
  }
  close(HOSTS_FILE);

  if ( ! @Rover::hosts_list ) {
    Rover::pwarn "Warning: No hosts to process.\n";
  }

  return(1);
}

sub load_module {
# We do this here so that exported functions are local to Rover, and not the calling interface.
# Expected argument are module file, and module name.  We let the calling program capture any
# errors via eval.
#

  my ($module_file, $module_name) = @_ ;

  require $module_file ;
  import $module_name ;
}

sub register_module {
# This function should be called by every module as it is loaded by rover
#
  my ($module_name, @module_variable_names) = @_;

  if ( ! $Rover::registered_modules{ $module_name } ) {
    my $exporter_name = $module_name ."::EXPORT";
    $Rover::registered_modules{ $module_name } = \@{ $exporter_name };

    foreach ( @{ $Rover::registered_modules{ $module_name } } ) {
      Rover::pdebug( "Registered function ". $module_name ."::$_\n" );
    }

    $Rover::registered_vars{ $module_name } = \@module_variable_names ;
  } else {
    Rover::pwarn "Warning: Module '$module_name' is already registered, use unregister_module() before re-registering\n";
  }

}

sub unregister_module {
# In the event that you no longer want to use a module, this should be called
# by the module unregistering iteself.
  my $module_name = shift;

  Rover::pdebug "Unregistering module '$module_name'\n";
  if ( $Rover::registered_modules{ $module_name } ) {
    delete $Rover::registered_modules{ $module_name };
    delete $Rover::registered_vars{ $module_name };
  } else {
    Rover::pwarn "Warning: Module '$module_name' was never registered.\n";
  }

}

sub process_hosts {
# Generic routine to process hosts in parralell.  It wont bother calling
# another routine if only one parallel process is requested.
#
  if ( ! $Rover::ipc_msg ) {
    $Rover::ipc_msg = new IPC::Msg(IPC_PRIVATE, S_IRWXU) || die "Could not create msg queue\n";
  }

 # Here we determine how to process hosts in parallel.
 #
  if ( $Config{useithreads} && $Rover::use_threads ) {
    Rover::pdebug("DEBUG: running hosts in parallel with threads\n");
    Rover::process_hosts_thread();
  } else {
    Rover::pdebug("DEBUG: running hosts in parallel with fork\n");
    Rover::process_hosts_fork();
  }

  return(1);
}

sub process_hosts_fork {
# Split the host list up and fork $Rover::parallel_process_count children
# processes.  Monitor activity via the ipc_ routines below.
#
  my $ppid = $$;
  my $pid;
  my $iteration;
  my $hosts_count = @Rover::hosts_list;
  my $hosts_process_count = int($hosts_count / $Rover::parallel_process_count);
  my $hosts_remainder = $hosts_count % $Rover::parallel_process_count;

 # Do the actual forking
 #
  if ( $hosts_count < $Rover::parallel_process_count ) {
    $Rover::parallel_process_count = $hosts_count;
  }
  $Rover::ipc_msg->snd(1000,"$$:CHILD_PROCESS_COUNT::$Rover::parallel_process_count",0);
  for ($iteration=0; $iteration<$Rover::parallel_process_count; $iteration++) {
    if (!defined($pid = fork())) {
      Rover::perror "Error could not fork child number ". $iteration + 1 ."\n";
      _exit(130);
    } elsif ($pid == 0) {
      last;
    }
    $Rover::global_process_current_status{$pid} = 'running';
  }

 # if we are the parent, monitor status via watcher routine.
 #
  if ($ppid == $$) {
    ipc_watcher_log_parse();

    my @children = keys %Rover::global_process_current_status ;
    foreach (@children) {
      waitpid($_, 0);
    }
    return(0);
  }

 # Fully daemonize and make sure if the watcher kills us to shut
 # down the running expect object and wait for children
 #
  setsid;

  local $SIG{INT} = sub {
	if ($Rover::exp_obj) {
          Rover::pdebug("DEBUG: Child $$, killing expect process pid: ". $Rover::exp_obj->pid() ."\n");

	  $Rover::exp_obj->send("exit;\rexit;\rexit;\r");
	  select(undef, undef, undef, 0.25);
	  $Rover::exp_obj->hard_close();
	}

	waitpid(-1, WNOHANG);
	_exit(0)
	};

 # Split up the host list
 #
  my $iteration_start = $iteration * $hosts_process_count;
  my $iteration_end;
  my @child_hosts;

  $iteration_end = $iteration_start + $hosts_process_count;

  for (my $i=$iteration_start; $i<$iteration_end; $i++) {
    push(@child_hosts, $Rover::hosts_list[$i]);
  }

  my $remainder_children = $Rover::parallel_process_count - $hosts_remainder - 1;
  if ($iteration > $remainder_children ) {
    push(@child_hosts, $Rover::hosts_list[$Rover::parallel_process_count *
	$hosts_process_count + ($iteration % $hosts_remainder)]);
  }

  open(STDERR, ">&STDOUT") || die "Error: child job $iteration exiting due to stdout errors\n";
  select(STDERR); $| = 1;	# make unbuffered
  select(STDOUT); $| = 1;	# make unbuffered

  foreach my $host_name (@child_hosts) {
    Rover::pdebug "DEBUG: $$: Child processing host '$host_name'\n";

    ipc_watcher_report($host_name);
    my $result = Rover::run_rules($host_name);
    ipc_watcher_report($host_name,$result);
  }
  ipc_watcher_report();

  _exit(0);
}

sub process_hosts_thread {
# Process each host as a thread, limiting the number of threads
# based on $Rover::parallel_process_count.
#

  my $thread_id = 0;
  my @thread_ids = (0..$Rover::parallel_process_count);

  $Rover::ipc_msg->snd(1000,"$$:CHILD_PROCESS_COUNT::1",0);

  foreach my $host_name (@Rover::hosts_list) {
   # Iterate through host list and spawn thread up to max
   #
    if ($thread_id < $Rover::parallel_process_count) {
      $thread_ids[$thread_id] = threads->new("run_rules",$host_name);
      ipc_watcher_report($host_name);
      $Rover::global_process_current_host[ $thread_ids[$thread_id]->tid ] = $host_name;
      $thread_id++;
    }

    if ($thread_id == $Rover::parallel_process_count) {
     # When the maximum number of threads is reached, wait for them to
     # terminate.
     #
      for (my $t=0; $t<$Rover::parallel_process_count; $t++) {
        my $result = $thread_ids[$t]->join();
        ipc_watcher_report($Rover::global_process_current_host[ $thread_ids[$t]->tid ], $result);

        $Rover::global_hosts_computed_tally++;
        $Rover::global_process_current_host[ $thread_ids[$t]->tid ] = "";
      }
      $thread_id = 0;
    }
  }

  if ( $thread_id > 0 ) {
   # When all hosts are read, clean up remaining threads by joining them
   #
    for (my $t=0; $t<$thread_id; $t++) {
      my $result = $thread_ids[$t]->join();
      ipc_watcher_report($Rover::global_process_current_host[ $thread_ids[$t]->tid ], $result);

      $Rover::global_hosts_computed_tally++;
      $Rover::global_process_current_host[ $thread_ids[$t]->tid ] = "";
    }
  }
  ipc_watcher_report();

 # Get all the messages sent to the msg queue
 #
  ipc_watcher_log_parse();
  return(1);
}

sub ipc_watcher_report {
# This is where children processes go to report to the parent what it
# has been doing.  Each child process must report when it has completed.
#
#
  my $arg_count = @_ ;
  my $message = "";

  my $hostname = shift;
  my $result = shift;
  my $info;
  if ( $arg_count == 3 ) { $info = shift; };

  if ( $hostname ne "" ) {
    if ( $result eq "" ) {
      $message = "$$:START:$hostname\n";
    } elsif ( $result == 255 ) {
      chomp $info ;
      $message = "$$:INFO:$hostname:$info\n";
    } elsif ( $result > 0 ) {
      $message = "$$:SUCCESS:$hostname\n";
    } elsif ( $result == -3 ) {
      $message = "$$:NO_ROOT:$hostname\n";
    } elsif ( $result == -4 ) {
      $message = "$$:CMD_FAILED:$hostname\n";
    } elsif ( $result == -99 ) {
      $message = "$$:CANCELED:$hostname\n";
    } else {
      $message = "$$:NO_SHELL:$hostname:$result\n";
    }
  } else {
    $message = "$$:CHILD_EXIT:\n";
  }

  $Rover::ipc_msg->snd(1000,$message,0);
  Rover::pdebug("DEBUG:\tIPC Reporter $$ sending: $message");
}

sub ipc_watcher_log_parse {
# The parent process (i.e. the watcher) calls this routine to monitor child
# activity.  No need to open any file handles prior to calling this.
#

  if ( $Rover::external_watcher ) {
    Rover::pdebug("DEBUG:\tIPC Watcher $$, returning due to external watcher\n");
    return(0);
  }

  my $buf;
  my $child_exit = 0;
  my $child_process_count = $Rover::parallel_process_count;
  my $stopped_processing = 0;
  while ( $Rover::ipc_msg->rcv($buf, 256) && $child_exit != $child_process_count ) {

    chomp $buf;
    Rover::pdebug("DEBUG:\tIPC Watcher $$, received: $buf\n");
    my ($child_pid,$status,$hostname,$result) = split(':',$buf);

    $Rover::global_process_current_status{$child_pid} = 'running' if $child_pid ;
    if ( $status eq "CHILD_PROCESS_COUNT" ) {
      $child_process_count = $result;

    } elsif ( $status eq "STOP_PROCESSING" ) {
      $stopped_processing = 1;

      my @processes = keys %Rover::global_process_current_status;
      Rover::pdebug("DEBUG:\tIPC Watcher $$, stopping processes: @processes\n");

      kill(2, @processes);

      foreach my $process_pid ( @processes ) {
        my $return = waitpid($process_pid, 0);
      }

    } elsif ( $status eq "CHILD_EXIT" ) {
      $Rover::global_process_current_status{$child_pid} = 'exited';
      $child_exit++ ;

    } elsif ( $status eq "CANCELED" ) {
      $Rover::global_process_current_status{$child_pid} = 'exited';
      push(@Rover::global_process_completed_hosts,$hostname);
      push(@Rover::report_failed_hosts,$hostname);
      Rover::pinfo($hostname, "Canceled");

      $child_exit++ ;

    } elsif ( $status eq "INFO" ) {
      Rover::pinfo($hostname, $result);

    } elsif ( $status eq "START" ) {
      Rover::pinfo($hostname, "Begining execution");
      $Rover::global_process_current_host{$child_pid} = $hostname;

    } elsif ( $status eq "SUCCESS" ) {
      Rover::pinfo($hostname, "Done");
      push(@Rover::global_process_completed_hosts,$hostname);
      $Rover::global_process_count++;

    } elsif ( $status eq "NO_SHELL" ) {
      push(@Rover::global_process_completed_hosts,$hostname);
      push(@Rover::report_failed_hosts,$hostname);
      $Rover::global_process_count++;

      if ( $result == 0 ) {
        Rover::pinfo($hostname, "Password error, failed to gain shell");
        $Rover::report_failed_password++;

      } elsif ( $result == -1 ) {
        Rover::pinfo($hostname, "Profile error, failed to gain shell");
        $Rover::report_failed_profile++;

      } elsif ( $result == -2 ) {
        Rover::pinfo($hostname, "Network error, failed to gain shell");
        $Rover::report_failed_network++;

      } else {
        Rover::pwarn "Error: child $child_pid returned result $result for status $status\n";
      }

    } elsif ( $status eq "NO_ROOT" ) {
      Rover::pinfo($hostname, "Failed to get root access");

      push(@Rover::global_process_completed_hosts,$hostname);
      push(@Rover::report_failed_hosts,$hostname);
      $Rover::report_failed_root++;
      $Rover::global_process_count++;

    } elsif ( $status eq "CMD_FAILED" ) {
      Rover::pinfo($hostname, "Failed in executing a command");

      push(@Rover::global_process_completed_hosts,$hostname);
      push(@Rover::report_failed_hosts,$hostname);
      $Rover::report_failed_runrules++;
      $Rover::global_process_count++;

    } else {
      Rover::pwarn "Error: child '$child_pid' returned unknown status: '$status'\n";
    }

    my $ds = $Rover::ipc_msg->stat;
    if ( ($child_process_count == $child_exit && $$ds[$Rover::msqid_ds_field] == 0) ||
		($stopped_processing && $$ds[$Rover::msqid_ds_field] == 0) ) {
      Rover::pdebug("DEBUG:\tIPC Watcher $$, Finished - $child_exit of $child_process_count exited, $$ds[$Rover::msqid_ds_field] messages in queue\n");
      last;
    }
    Rover::pdebug("DEBUG:\tIPC Watcher $$, Returning to queue - $child_exit of $child_process_count exited, $$ds[$Rover::msqid_ds_field] messages in queue\n");
  }
  $Rover::ipc_msg->remove();
  $Rover::ipc_msg = undef;

}

sub run_rules {
# Run stored routines on a single host.  This will stop processing if one single
# command fails, or if no shell or root access is available.
#
  my $hostname = shift;

  $Rover::exp_obj = Rover::get_shell($hostname);
  if ( $Rover::exp_obj <= 0 ) {
    return($Rover::exp_obj);
  }
  $Rover::exp_obj->clear_accum();

 # Determine OS type and store results
 #
  my $os_type = "";
  $Rover::exp_obj->send("uname -a #UNAME\n");
  $Rover::exp_obj->expect(4,
	[ 'HP-UX', sub { $os_type = 'HP_UX'; exp_continue; } ],
	[ 'AIX', sub { $os_type = 'AIX'; exp_continue; } ],
	[ 'SunOS', sub { $os_type = 'SunOS'; exp_continue; } ],
	[ 'hostfax', sub { $os_type = 'hostfax'; exp_continue; } ],
	[ 'not found', sub { $os_type = 'UNKNOWN'; exp_continue; } ],
	[ 'syntax error', sub { $os_type = 'UNKNOWN'; exp_continue; } ],
	[ 'BSD/OS', sub { $os_type = 'BSD_OS'; exp_continue; } ],
	[ 'C:', sub { $os_type = 'Windows'; 
			# Send appropriate return because \n didn't work.
                        my $fh = shift;
                        select(undef, undef, undef, $Shell_Access_Routines::my_slow);
                        $fh->send(""); } ],
	[ 'Linux', sub { $os_type = 'Linux'; exp_continue; } ],
	[ timeout => sub { Rover::perror "$hostname:\tError: running uname -a timed out, server may be running too slow\n"; } ],
	'-re', $Rover::user_prompt, );

  Rover::pwarn "$hostname:\tWarning: unknown os type, running ALL and UNKNOWN commands\n" if $os_type eq 'UNKNOWN';
  $Rover::exp_obj->clear_accum();

  my $os_name = "Rover::$os_type";
  my $success;

  foreach ( @$os_name,@Rover::ALL ) {
   # This is the actual work as defined by OS => Ruleset.  If one command fails, stop execution
   # and exit with failure.
   #
    my $failed_commands = 0;

    if ( $Rover::expert_mode ) {
     # Expert mode is executed as an entire perl block of code.  We only catch
     # runtime errors here.  Hey, your the expert, use your own sanity checking!
     #
      if ( @{$Rover::rulesets{$_}} ) {
        Rover::pinfo($hostname,"running $os_type ruleset '$_'");
        eval "@{$Rover::rulesets{$_}}";

        if ( $@ ) {
          Rover::pinfo($hostname, "Error, $@");
          $failed_commands++;
          $success = -4;
        };
      }

    } else {
      foreach my $command ( @{$Rover::rulesets{$_}} ) {
        my $subroutine = $command;
        $subroutine =~ s/\(.*// ;
        $subroutine =~ s/ //g ;

        my $args = $command;
        $args =~ s/$subroutine// ;
        $args =~ s/^[\s\t]*\(// ;
        $args =~ s/\);[\s\t]*$// ;

        my $args_sub = substr($args,0,20);
        $args_sub .= "...";
        Rover::pdebug("DEBUG: $hostname: running $subroutine($args_sub)\n");
        Rover::pinfo($hostname, "running $subroutine($args_sub)");
        eval {
          $success = &$subroutine($args, $Rover::exp_obj, $hostname, $os_type);
        };

        if (! $success || $@ ) {
          $success = -4;
          $failed_commands++;
          last;
        }
      }
    }

    if ( $failed_commands ) {
      last;
    }
  }

  if ( ! $Rover::exp_obj <= 0 ) {
    $Rover::exp_obj->send("exit;\rexit;\rexit;\r");
    $Rover::exp_obj->hard_close();
    select(undef, undef, undef, 0.25);
  }

  $Rover::exp_obj = undef;
  return($success);
}

sub get_shell {
# Get expect object for shell access and/or root privilages
#
  my $hostname = shift;

  if ( ! @Rover::shell_access_routines ) {
    Rover::perror "Error: No shell access routines specified, cannot continue\n";
    return(0);
  }

  my $exp_obj;
  foreach my $shell_access_routine (@Rover::shell_access_routines) {
   # Run each shell access routine, stop if one succeeds or no more routines left
   #
    Rover::pdebug "DEBUG: $hostname: Attempting to gain shell access with routine $shell_access_routine\n";
    eval {
      $exp_obj = &$shell_access_routine($hostname,$Rover::user,@Rover::user_credentials);
    };
    Rover::pinfo($hostname, "Error gaining shell: $@") if $@ ;

    if ( $exp_obj <= 0 ) {
      Rover::pdebug "DEBUG: $hostname:\tshell access routine $shell_access_routine failed\n";
      if ( $exp_obj == 0 || $exp_obj == -1 ) { last; } # Dont continue if password or profile is wrong

    } else {
      last;
    }
  }

  if ( $exp_obj <= 0 ) {
   # Return code was an error, evaluate and increment appropriate counters
   #
    #if ( $exp_obj eq "" ) { $exp_obj = 0; }	# Happens every now and then, not sure why

    Rover::pdebug "DEBUG: $hostname:\tError in gaining shell, result was $exp_obj\n";
    return ($exp_obj);
  }

  if ( $Rover::root_access_required ) {
    Rover::pinfo($hostname, "Becoming Root");

    my $result = 0;
    foreach my $routine ( @Rover::root_shell_access_routines ) {
     # Iterate through any root shell access routines.  If we cant get root then increment
     # counters and return with error
     #
      Rover::pdebug "DEBUG: $hostname: root_shell_access: attempting to get root with routine: '$routine'\n";
      eval {
        $result = &$routine($exp_obj,$hostname);
      };

      if ( $result && ! $@ ) { last; }
      Rover::pwarn "$hostname:\tWarning: root access routine failed: '$routine'\n";
    }
    Rover::pdebug("DEBUG: $hostname: done getting root, result is $result\n");
    if ( ! $result ) {
      $exp_obj->send("exit;\rexit;\rexit;\r");

      return(-3);
    }
  }

  return($exp_obj);
}

END {
  if ( $Rover::ipc_msg ) {
    $Rover::ipc_msg->remove;
  }
}

1;
__END__;

=head1 NAME

Rover - Run arbitrary commands on remote Unix servers

=head1 VERSION

2.02

=head1 USAGE

Rover comes with two frontend programs, rover and rovergtk.
The main program, rover, is designed to be run from the
command line.  rovergtk uses the perl module Gtk to provide
a graphical user interface.

=head1 DESCRIPTION

Rover is designed to provide a means of executing commands on remote systems.
In order to make Rover do something you have to provide a list of hosts, one
or more rulesets, and on what OS each ruleset is to be run.

A ruleset is a group of commands to be ran on remote systems.  Each rule
within the ruleset uses an exported function provided by exntension modules.
Some examples are provided in the B<EXAMPLES> section.

The core Rover module doesnt do more then direct the way things will be
executed.  Loadable modules are required to extend the functionality and
provide commands for rulesets to use.

Modules included with Rover:

    Shell_Access_Routines
    Root_Access_Routines
    Run_Commands
    File_Transfer
    User_Admin
    Password

=head1 FILES

=over 4

=item ~/.rover/config.run

The config file is the primary means of controlling rover. This
is where rulesets are defined, modules are loaded, and OSs are given rulesets
to run.

The config file, by default is located in $HOME/.rover directory.
The name and location can be overridden from the command line (using rover).

This configuration file has three sections: OS ruleset definition, General
configuration, and Ruleset definitions.

=over 4

=item OS Ruleset Section

The OS ruleset definition defines what rulesets will be executed on a particular
OS.  Alternatively, the reserved word "ALL" (all caps) can be used to specify all
OS's.  Valid OS names are any value returned by "uname -s".  Spaces are allowed 
before and after, however, there should be no space between the OS, colon 
separator, and the ruleset name.

Syntax for OS section is:

    <OS Name>:<Ruleset Name>;

=item General Section

The general configuration section consist of Perl code that will be executed 
during configuration.  Any custom modules that are to be loaded should be placed 
here, along with global variables that are to be overridden.  The general 
configuration section takes the same form as a ruleset definition, except the 
rule name is "GENERAL".

Syntax for the general configuration section is as follows:

    GENERAL:{
      use <Custom Module>;
      [ other inline perl commands ];
      ...
    };

=item Ruleset Definition Section

The ruleset definition section defines what is to be done in a particular rule.
Each rule will have in it functions to execute with one parameter.  These are
typically functions defined by modules loaded via the general configuration
section.  Valid ruleset names can only consist of valid Perl variable characters.
Please refer to Perl documentation for further explanation.

Syntax for ruleset definitions:

    <Ruleset name>:{
        <command>(parameter);
        ...
    };

With expert mode turned on ($Rover::export_mode = 1;), code within all ruleset
definitions will be executed as blocks of Perl code.  This is useful if you 
what to introduce loops or condition statements.  Be advised, however, that
when using expert mode, custom modules are not parsed and will have to be passed
the appropriate values.

For example, when in normal mode, if RunCommands.pm is used, executing a complicated
command such as "ps -ef|awk 'NR > 1 {print $1}'|sort -n|uniq" within the
"ALL_Cmnds" ruleset would look like this:

      ALL_Cmnds:{
          execute(ps -ef|awk 'NR > 1 {print $1}'|sort -n|uniq);
      };

However, when using expert mode, you must pass the argument as a scalar, and
include the expect object, hostname, and os type as follows:

      ALL_Cmnds:{
          execute('ps -ef|awk \'NR > 1 {print $1}\'|sort -n|uniq',$exp_obj,$hostname,$os_type);
      };

Making sure, as is shown in this example, to escape the string properly.

=back

=item ~/.rover/hosts.txt

The hosts.txt file is where all the host information is stored.  The basic format
of this file is one host name per line.  However, additional information can be
added in the form of a comma separated list.  The additional information is
stored as a reference to an array in the hash %Rover::hosts_info, with the hostname
as the key.

=head1 MODULES

There are 4 types of modules that can be built to extend Rover functionality:
Shell access routines, root access routines, root password storage routines,
and custom expect modules.

All modules have access to various Rover configuration variables.  Please see
the VARIABLES section for details regarding these.

When writing custom modules, it is extremely helpful to observe the debug option
when deciding to print to standard out.  $Rover::debug generally has three levels
of operation: 0 = Standard output and Errors, 1 = Warning messages, >1 = Debugging
output.

=item Shell access routines

The Shell_Access_Routines.pm module already ships with Rover.  This provides 
means of logging into a remote server via ssh, telnet, or rlogin.  This should
be all that is ever needed to create a shell expect object for Rover.

In order to write a custom shell access routine, the following items must be
considered.

1. Rover will call your shell access routine if the name of the function exists
inside the @Rover::shell_access_routines array.

2. Rover will pass only the hostname/ip address of the server needing shell access.

3. Rover expects an Expect.pm object or error code to be returned.  Error codes are:

     0 = Failed password
    -1 = Profile error
    -2 = Network connection error

4. Global variables to consider when writing custom shell access routines:

    $Rover::user
    @Rover::user_credentials
    $Rover::user_prompt
    $Rover::user_prompt_force
    $Rover::logs_dir

=item Root access routines

Root_Access_Routines.pm module, which also ships with Rover, supplies methods
of gaining elevated privileges for user root, via the "su" and "sudo" command.
Read the appropriate documentation regarding its usage.

For custom modules, the following items must be considered:

1. Rover will call root access routines stored in @Rover::root_shell_access_routines
array.

2. Rover will call each root access routine with two arguments, the Expect.pm
object, and the hostname.

3. Routines must exit with either success or failure.

4. Relevant variables are as follows:

    %Rover::root_password_hash
    @Rover::root_password_list

=item Root password storage

Rover, by default, will gather a list of root passwords from the command line and
stuff them into @Rover::root_password_list.  However, as more complicated 
environments emerge, and secure password storage solutions vary, Rover provides
a mechanism to extend root password collections.

Writing a root password storage module is extremely easy, Rover does not supply
a function with any parameters, and only checks for success or failure on completion.
In order to get your storage routine to run during Rover execution, the name
must be pushed onto the @Rover::root_password_storage_routines array.

The expected process to occur is for root passwords to be placed into the global
hash %Rover::root_password_hash, with the key being the hostname/ip, and the value
being the root password.  Alternatively, populating @Rover::root_password_list could
be useful as well.

As for how root passwords are gathered is entirely up to the programmer.

=item Custom expect module

Once all the objectives above have been completed (that is you have an Expect
object created with shell/root access to a remote Unix/Linux system), the true
value of Rover lies in its ability to use this access to run arbitrary administrative
functions.

Rover ships a very basic Run_Commands.pm module, which exports the execute() and
send() routines.  execute() simply runs whatever is passed as an argument on the
remote host.  The routine send() does the same, only it does not wait for the
prompt to be returned.  Read the documentation for Run_Commands.pm for more
detail on this module.

For more advanced tasks, custom modules must be written and imported during runtime
for rover to utilize them.  Considerations are as follows:

1. Custom modules should exist somewhere in the @INC search path.

2. Modules are not automatically imported, users must specify to use them in the
~/.rover/config.run file in the GENERAL section.

3. Exported commands ran inside a ruleset are called with four parameters:

    1. Arguments supplied inside ~/.rover/config.run ruleset definition
    2. The expect object
    3. Hostname/IP address
    4. OS type.

4. Return values should be true or false, execution on any particular host will
be terminated when one ruleset command fails.

5. Routines will be ran in parallel and should be thread safe (regardless of
the fact that IO::Tty is not).

See the FILES section for more details on importing custom modules and executing
them inside rulesets.

=head1 VARIABLES

=over 4

=item $Rover::user

By default this is $ENV{USER}.  This is the the name specified when logging into
a remote server.

=item @Rover::user_credentials

Array of passwords to try when logging in.  See B<perldoc Rover::Shell_Access_Routines>
for specifics on how this is used.

=item $Rover::user_prompt

For Expect to determine when a shell is ready for a command, $Rover::user_prompt should
contain a regular expression string to search for.  The default should work for most
prompts.

=item $Rover::user_prompt_force

If a timeout occures waiting for a prompt, this value is used to change the PS1 variable.

=item $Rover::debug

Output level is determined by this integer.  0 is normal message displaying, 1 is normal
plus warnings, 2 is full Rover debuging mode.

=item $Rover::expert_mode

Whith expert mode turned on, rulesets are executed as blocks of perl code, instead of
parsing each rule.  See the /Ruleset Definition/ portion of the B<FILES> section for
more details.

=item %Rover::rulesets

Hash of ruleset definitions.  The key is the ruleset name, values are scalar pointers
to the ruleset array.

=item $Rover::use_threads

Use threading instead of forks.  See B<NOTES> section for more detail.

=item $Rover::parallel_process_count

Number of forks to run in parallel, or number of concurrent threads.

=item $Rover::external_watcher

Used mainly by the gui, this specifies that an external process will be monitoring child
activity in $Rover::ipc_msg.

=item @Rover::hosts_list

List of host names/ip addresses to run rulesets against.

=item %Rover::hosts_data

Hash of extra host information.  The key is the hostname, the value is a scalar address
to an array of the information.  See the /hosts.txt/ portion of B<FILES> section.

=item $Rover::config_file

Location of the config file.  Default is $HOME/.rover/config.run, a default config.run
is created if it does not exist.

=item $Rover::hosts_file

Location of the hosts file.  Default is $HOME/.rover/hosts.txt.  An error is displayed if
no hosts file exists.

=item $Rover::logs_dir

Directory to place Expect logs for each host.  Default is $HOME/.rover/logs.  If the directory
does not exist, it is created.

=item $Rover::ipc_msg

This is an IPC message queue used by the watcher process to get status information from the
child process(es).  This is how success and failure is gathered by the parent process during
each run (when using forks).

=item @Rover::ALL

List of ruleset names to run on all systems.

=item @Rover::UNKNOWN

If uname does not return an OS type, or returns one that Rover doesnt know about, rulesets
within this array are used.  This is helpful for systems without the uname command (like routers).

=item @Rover::Linux

List of ruleset names to run on Linux systems.

=item @Rover::AIX

List of ruleset names to run on AIX systems.

=item @Rover::SunOS

List of ruleset names to run on SunOS systems.

=item @Rover::HP_UX

List of ruleset names to run on HP-UX systems.  Note that the hyphin is converted to an underscore.
This is done because perl does not like hyphins inside variable names.

=item @Rover::FreeBSD

List of ruleset names to run on FreeBSD systems.

=item @Rover::OpenBSD

List of ruleset names to run on OpenBSD systems.

=item @Rover::Windows

List of ruleset names to run on Windows systems.

=item %Rover::registered_modules

When a module is plugged into Rover, it should register itself.  This is hash of module names.
The key is the module name, the value is a scalar address to a list of exported functions.

=item %Rover::registered_vars

Hash of variables available for configuration within each module.  The key is the module name,
the value is a scalar address to a list of variable names.  Varaible names are expected to contain
thier type identifiers ($, @, or %).

=item @Rover::shell_access_routines

List of function names to call in order to gain shell access to a server.  An Expect object is
the expected return value.  See the B<MODULES> section for more details.  Rover::Shell_Access_Routines
automatically populates this list.

=item @Rover::root_shell_access_routines

List of function names to use in order to aquire root.  These are ran after shell is aquired, and
only if $Rover::root_access_required is true.  Rover::Root_Access_Routines automatically populates
this list.

=item @Rover::root_password_storage_routines

List of function names to call when aquiring root passwords.  See B<MODULES> section for more details.

=item $Rover::root_access_required

Value to determine if root is needed.  Zero(0) is false, one(1) is true.

=item %Rover::root_password_hash

Hash of root passwords.  The key is the hostname, the value is the password.

=item @Rover::root_password_list

List of root passwords to try.  Rover::Root_Access_Routines::get_root_by_su() will try every value
before giving up.

=item @Rover::report_failed_hosts

List of hosts that reported failures of any kind.

=item $Rover::report_failed_profile

Number of hosts that failed because the profile wasnt configured to use the correct prompt.  Could
also be that the system is running slow, or the profile took to long to finish running.

=item $Rover::report_failed_password

Number of hosts where password(s) stored in @Rover::user_credentials were not correct.

=item $Rover::report_failed_network

Number of hosts that were not available on the network.

=item $Rover::report_failed_root

Number of hosts where we could not get root access after successfully aquiring a shell.

=item $Rover::report_failed_runrules

Number of hosts where a ruleset failed to execute.

=item $Rover::parent_id

Internal use only, value of parent process, also known as the ipc_watcher.

=item $Rover::global_process_count

Number of hosts completed, regardless of completion status.

=item @Rover::global_process_completed_hosts

List of hosts completed, regardless of completion status.

=item %Rover::global_process_current_host

Hash of hosts currently being executed.  Key is PID of child process, or thread id of
the a host currently being executed.

=item %Rover::global_process_current_status

Hash of children processes currently running.  Key is process ID, value is either 'running'
or 'exited'.

=back

=head1 EXAMPLES

=over 4

Here is an example config.run file that can be used by Rover:

    ALL:Unix_Uptime;
    Linux:CPU_Info;
    
    Unix_Uptime:{
        execute(uptime);
    };
    
    CPU_Info:{
        execute(cat /proc/cpuinfo);
    };
    
    GENERAL:{
        $Rover::user = 'another';
        $Rover::debug = 1;
    
        use Rover::Shell_Access_Routines qw( shell_by_ssh );
        use Rover::Root_Access_Routines;
        use Rover::Run_Commands;
    
        @Rover::shell_access_routines = qw( shell_by_ssh );
    };

Now lets disect this file by each section.

    ALL:Unix_Uptime;
    Linux:CPU_Info;

In these two lines we are telling Rover that we want all OS types to
run the Unix_Uptime ruleset.  In addition to that, we say hosts of OS
type Linux will run the CPU_Info ruleset.

    Unix_Uptime:{
        execute(uptime);
    };

    CPU_Info:{
        execute(cat /proc/cpuinfo);
    };

Here we define both the Unix_Uptime and CPU_Info rulesets.  We use
the function 'execute()', supplied by the Rover::Run_Commands module.

    GENERAL:{
        $Rover::user = 'another';
        $Rover::debug = 1;

        use Rover::Shell_Access_Routines qw( shell_by_ssh );
        use Rover::Root_Access_Routines qw( get_root_by_su get_root_by_sudo );
        use Rover::Run_Commands;

        @Rover::shell_access_routines = qw( shell_by_ssh );
    };

In this GENERAL block, we override a few rover variables, $Rover::user, and
$Rover::debug.

The next three lines we import the modules: Rover::Shell_Access_Routines,
Rover::Root_Access_Routines, and Rover::Run_Commands.  When we load both
root and shell access routines, we also specify which functions we want
to import.

Finally, we override the values in @Rover::shell_access_routines, and chose
only to use shell_by_ssh.  If we had not chosen to import shell_by_ssh when
loading Rover::Shell_Access_Routines, we would have had to specify the full
module path Rover::Shell_Access_Routines::shell_by_ssh.

It is important to remember that each line in the GENERAL section is executed
as a complete perl command.  Entering multiple line commands will not work.

=back

=head1 NOTES

=item On Threading

Rover is quite capable of using threads to process hosts in parallel.
The advantage is that it uses fewer resources then forking.

The reason threads will probably not work for you is that in order to
spawn commands and expect on top of them, the IO::Tty module is called to
create a pseudo terminal.  This module is not thread safe, and thus breaks
everything on top trying to thread with it.

If you really really want to thread, using telnet and ftp will get the
job done.  Both implementations are 100% perl, and require no terminal
for expect to interact.

I have worked with Net::SSH::Perl and Net::SSH2, and at the moment
neither are suitible for inclusion.  If a thread safe, 100% perl
implementation of SSH does comes along, then I'll revisit making
threads work all around.  Until then, happy forking.

=head1 AUTHORS

  Bryan A Bueter
  Erik McLaughlin
  Jayson A Robinson

=head1 LICENSE

This module can be used under the same terms as Perl.

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

