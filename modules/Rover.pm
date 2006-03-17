#***************************************************************************
# Rover package: 08/05/2004
# Last modified by: BAB
#
# WARNING: Do not modify this file, read the documentation and learn how to
# use the commands.run file to configure what you need.
#
#****************************************************************************
package Rover;

require 5.8.0;

use Config;
use Expect;

if ( $Config{useithreads} ) {
  require threads;
  require Thread::Semaphore;
}

use Exporter;

our $VERSION = '0.00';
our $AUTHORS = 'Bryan A. Bueter, Erik McLaughlin, Jayson A. Robinson';

@Rover::ISA = qw( Exporter );
@Rover::EXPORT = qw( build_config read_authentication process_hosts @Rover::shell_access_routines );

use strict 'vars';
use strict 'subs';
use Expect;

BEGIN {
 # General Rover configuration variables
  $Rover::user = $ENV{"USER"};
  @Rover::user_credentials = ();
  $Rover::user_prompt = '\$\s$';
  $Rover::user_prompt_force = '$ ';

  $Rover::debug = 0;
  $Rover::expert_mode = 0;
  %Rover::rulesets;
  $Rover::use_threads = 0;
  $Rover::paralell_process_count = 4;
  @Rover::hosts_list = ();

 # File locations
  $Rover::config_file = "commands.run";
  $Rover::hosts_file = "hosts.txt";
  $Rover::logs_dir = "./logs";
  $Rover::ipc_fifo = "./.messages";

 # Arrays to store rulesets by platform.  Platform names should have
 # hyphins(-) converted to underscores(_).
  @Rover::AIX = ();
  @Rover::SunOS = ();
  @Rover::HP_UX = ();
  @Rover::BSD_OS = ();
  @Rover::Windows = ();
  @Rover::Linux = ();
  @Rover::UNKNOWN = ();
  @Rover::ALL = ();

 # Global routines arrays
  @Rover::shell_access_routines = ();
  @Rover::root_shell_access_routines = ();
  @Rover::root_password_storage_routines = ();

 # Root password objects
  $Rover::root_access_required = 0;
  %Rover::root_password_hash;
  @Rover::root_password_list;

 # Reporting statistics
  $Rover::report_semaphore = undef;
  @Rover::report_failed_hosts = ();
  $Rover::report_failed_profile = 0;
  $Rover::report_failed_password = 0;
  $Rover::report_failed_network = 0;
  $Rover::report_failed_root = 0;
  $Rover::report_failed_runrules = 0;

  $Rover::parent_id = $$;
  $Rover::global_process_count = 0;
  @Rover::global_process_completed_hosts;
  %Rover::global_process_current_host;
  %Rover::global_process_current_status;

 # Set some expect values
  $Expect::Debug = 0;
  $Expect::Log_Stdout = 0;
}

sub build_config {

  if (! stat($Rover::config_file) ) {
    print STDERR "Error: rover config file does not exist '$Rover::config_file'\n";
    return(0);
  }

  if (! stat($Rover::hosts_file) ) {
    print STDERR "Error: rover hosts file does not exist '$Rover::hosts_file'\n";
    return(0);
  }

  my $current_rule = "";
  my $current_rule_array = 0;
  my $inrule = 0;
  my $count = 0;
  my $instance = 0;

  open(CONFIG_FILE,$Rover::config_file);
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
          print "\tDEBUG: Pushing ruleset '$tmp_rule' to OS '$os'\n" if $Rover::debug > 1;
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
          print "\tDEBUG: Setting general rule: $_\n" if $Rover::debug > 1;
          eval $_;
          next;
        }

        print "\tDEBUG: Pushing command for rule '$current_rule': '$_'\n" if $Rover::debug > 1;
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

  open(HOSTS_FILE,$Rover::hosts_file);
  my $host_count = 1;
  print "Reading in Hosts File ...\n" if $Rover::debug;
  while (<HOSTS_FILE>) {
    chomp $_;

    if (! gethostbyname($_) ) {
      print STDERR "Error: Unable to resolve hostname/address: $_, server will not be included\n";
      next;
    }
    print "  $host_count.\t$_\n" if $Rover::debug;
    $host_count++;
    push(@Rover::hosts_list, $_);
  }
  close(HOSTS_FILE);

  if ( ! @Rover::hosts_list ) {
    die "No hosts to process, exiting without doing anything\n";
  }
  if ( $Rover::expert_mode && $Rover::debug ) {
    print "Warning: Using expert mode, I hope you know what your doing...\n\n";
  }
  return(1);
}

sub read_authentication {
  print STDERR $Rover::user,"'s password: ";
  system("stty -echo");
  my $user_pass = <STDIN>;
  chomp $user_pass;
  while ( $user_pass ne "" ) {
    print STDERR "\n";
    push(@Rover::user_credentials, $user_pass);

    print STDERR $Rover::user,"'s password: ";
    $user_pass = <STDIN>;
    chomp $user_pass;
  }
  print STDERR "\n";
  system("stty echo");

  if ( $Rover::root_access_required ) {
   # We need to get root, store root passwords either with pre-defined
   # storage routines or from the command line
   #
    if ( ! @Rover::root_password_storage_routines ) {
     # If there are no root password storage routines defined, get a list
     # of root passwords from the command line.
     #
      print STDERR "\nroot's password: ";
      system("stty -echo");
      my $root_pass = <STDIN>;
      chomp $root_pass;
      while ( $root_pass ne "" ) {
        print STDERR "\n";
        push(@Rover::root_password_list, $root_pass);

        print STDERR "root's password: ";
        $root_pass = <STDIN>;
        chomp $root_pass;
      }
      print STDERR "\n\n";
      system("stty echo");

    } else {
     # Iterate through root password storage routines until one is successful.
     # die if all fail.
     #
      my $result = 0;
      foreach my $routine ( @Rover::root_password_storage_routines ) {
        $result = &$routine();

        if ( $result ) { last; }

        print "Warning: root password storage routine failed: '$routine'\n" if $Rover::debug > 1;
      }
      if ( ! $result ) {
      my $result = 0;
        die "Unable to store root passwords, exiting\n";
      }
    }
  }

  return(1);
}

sub process_hosts {
# Generic routine to process hosts in parralell.  It wont bother calling
# another routine if only one paralell process is requested.
#
  if ( $Rover::paralell_process_count == 1 ) {
   # If hosts are to be executed one at a time, we just do it
   # here, rather then creating a new routine.
   #
    foreach my $host_name (@Rover::hosts_list) {
      Rover::run_rules($host_name);
    } # end of foreach $host_name

  } else {
   # Here we determine how to process hosts in paralell.
   #
    if ( $Config{useithreads} && $Rover::use_threads ) {
      Rover::process_hosts_thread();
    } else {
      Rover::process_hosts_fork();
    }

  }

  return(1);
}

sub process_hosts_fork {
# Split the host list up and fork $Rover::paralell_process_count children
# processes.  Monitor activity via the ipc_ routines below.
#
  my $ppid = $$;
  my $pid;
  my $iteration;
  my $hosts_count = @Rover::hosts_list;
  my $hosts_process_count = int($hosts_count / $Rover::paralell_process_count);
  my $hosts_remainder = $hosts_count % $Rover::paralell_process_count;

  if ( ! -p $Rover::ipc_fifo ) {
    system("rm -f $Rover::ipc_fifo ; mknod $Rover::ipc_fifo p");
  }

 # Do the actual forking
 #
  if ( $hosts_count < $Rover::paralell_process_count ) {
    $Rover::paralell_process_count = $hosts_count;
  }
  for ($iteration=0; $iteration<$Rover::paralell_process_count; $iteration++) {
    if (!defined($pid = fork())) {
      print STDERR "Error could not fork child number ". $iteration + 1 ."\n";
      exit(130);
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

 # Split up the host list
 #
  my $iteration_start = $iteration * $hosts_process_count;
  my $iteration_end;
  my @child_hosts;

  $iteration_end = $iteration_start + $hosts_process_count;

  for (my $i=$iteration_start; $i<$iteration_end; $i++) {
    push(@child_hosts, $Rover::hosts_list[$i]);
  }

  my $remainder_children = $Rover::paralell_process_count - $hosts_remainder - 1;
  if ($iteration > $remainder_children ) {
    push(@child_hosts, $Rover::hosts_list[$Rover::paralell_process_count *
	$hosts_process_count + ($iteration % $hosts_remainder)]);
  }

  open(STDERR, ">&STDOUT") || die "Error: child job $iteration exiting due to stdout errors\n";
  select(STDERR); $| = 1;	# make unbuffered
  select(STDOUT); $| = 1;	# make unbuffered

  open(FIFO_OUT,">$Rover::ipc_fifo") or die "Error: $$: Child could not open fifo '". $Rover::ipc_fifo ."' for writing\n";
  select((select(FIFO_OUT), $| = 1)[0]);
  foreach my $host_name (@child_hosts) {
    print "\tDEBUG: $$: Child processing host '$host_name'\n" if $Rover::debug > 1;

    ipc_watcher_report($host_name);
    my $result = run_rules($host_name);
    ipc_watcher_report($host_name,$result);
  }
  ipc_watcher_report();

  exit(0);
}

sub process_hosts_thread {
# Process each host as a thread, limiting the number of threads
# based on $Rover::paralell_process_count.
#
# Currently this is useless uless you want to experiment.
#

  my $thread_id = 0;
  my @thread_ids = (0..$Rover::parallell_process_count);

  $Rover::report_semaphore = new Thread::Semaphore;

  foreach my $host_name (@Rover::hosts_list) {
   # Iterate through host list and spawn thread up to max
   #
    if ($thread_id < $Rover::paralell_process_count) {
      $thread_ids[$thread_id] = threads->new("run_rules",$host_name);
      $Rover::global_process_current_host[ $thread_ids[$thread_id]->tid ] = $host_name;
      $thread_id++;
    }

    if ($thread_id == $Rover::paralell_process_count) {
     # When the maximum number of threads is reached, wait for them to
     # terminate.
     #
      for (my $t=0; $t<$Rover::paralell_process_count; $t++) {
        $thread_ids[$t]->join();
        $Rover::global_hosts_computed_tally++;
        push(@Rover::global_process_completed_hosts,$Rover::global_process_current_host[ $thread_ids[$t]->tid ]);
        $Rover::global_process_current_host[ $thread_ids[$t]->tid ] = "";
      }
      $thread_id = 0;
    }
  }

  if ( $thread_id > 0 ) {
   # When all hosts are read, clean up remaining threads by joining them
   #
    for (my $t=0; $t<$thread_id; $t++) {
      $thread_ids[$t]->join();
      $Rover::global_hosts_computed_tally++;
      push(@Rover::global_process_completed_hosts,$Rover::global_process_current_host[ $thread_ids[$t]->tid ]);
      $Rover::global_process_current_host[ $thread_ids[$t]->tid ] = "";
    }
  }

  return(1);
}

sub ipc_watcher_report {
# This is where children processes go to report to the parent what it
# has been doing.  Each child process must report when it has completed.
# Children must already have FIFO_OUT file handle opened appropriatly before
# calling this routine.
#
  my $arg_count = @_ ;
  my $message = "";

  my $hostname = shift;
  my $result = shift;

  if ( $hostname ne "" ) {
    if ( $result eq "" ) {
      $message = "$$:START:$hostname\n";
    } elsif ( $result > 0 ) {
      $message = "$$:SUCCESS:$hostname\n";
    } elsif ( $result == -3 ) {
      $message = "$$:NO_ROOT:$hostname\n";
    } elsif ( $result == -4 ) {
      $message = "$$:CMD_FAILED:$hostname\n";
    } else {
      $message = "$$:NO_SHELL:$hostname:$result\n";
    }
  } else {
    $message = "$$:CHILD_EXIT:\n";
  }

  print FIFO_OUT $message;
}

sub ipc_watcher_log_parse {
# The parent process (i.e. the watcher) calls this routine to monitor child
# activity.  No need to open any file handles prior to calling this.
#

  open(FIFO_IN,$Rover::ipc_fifo) or die "Error: $$: Parent process could not open fifo '". $Rover::ipc_fifo ."' for reading\n";
  while (<FIFO_IN>) {
    chomp $_;
    my ($child_pid,$status,$hostname,$result) = split(':',$_);

    if ( $status eq "CHILD_EXIT" ) {
      $Rover::global_process_current_status{$child_pid} = 'exited';

    } elsif ( $status eq "START" ) {
      $Rover::global_process_current_host{$child_pid} = $hostname;

    } elsif ( $status eq "SUCCESS" ) {
      push(@Rover::global_process_completed_hosts,$hostname);
      $Rover::global_process_count++;

    } elsif ( $status eq "NO_SHELL" ) {
      push(@Rover::global_process_completed_hosts,$hostname);
      push(@Rover::report_failed_hosts,$hostname);
      $Rover::global_process_count++;

      if ( $result == 0 ) {
        $Rover::report_failed_password++;

      } elsif ( $result == -1 ) {
        $Rover::report_failed_profile++;

      } elsif ( $result == -2 ) {
        $Rover::report_failed_network++;

      } else {
        print STDERR "Error: child $child_pid returned result $result for status $status\n";
      }

    } elsif ( $status eq "NO_ROOT" ) {
      push(@Rover::global_process_completed_hosts,$hostname);
      push(@Rover::report_failed_hosts,$hostname);
      $Rover::report_failed_root++;
      $Rover::global_process_count++;

    } elsif ( $status eq "CMD_FAILED" ) {
      push(@Rover::global_process_completed_hosts,$hostname);
      push(@Rover::report_failed_hosts,$hostname);
      $Rover::report_failed_runrules++;
      $Rover::global_process_count++;

    } else {
      print STDERR "Error: child '$child_pid' returned unknown status: '$status'\n";
    }

    my @children = keys %Rover::global_process_current_status;
    my $continue = 0;
    foreach (@children) {
      if ( $Rover::global_process_current_status{$_} eq 'running' ) {
        $continue = 1;
        last;
      }
    }
    if ( ! $continue ) { last; };
  }
  close(FIFO_IN);

}

sub run_rules {
# Run stored routines on a single host.  This will stop processing if one single
# command fails, or if no shell or root access is available.
#
  my $hostname = shift;

  my $exp_obj = Rover::get_shell($hostname);
  if ( $exp_obj <= 0 ) {
    if ( $Config{useithreads} && $Rover::use_threads ) {
      exit($exp_obj);
    } else {
      return($exp_obj);
    }
  }
  $exp_obj->clear_accum();

 # Determine OS type and store results
 #
  my $os_type = "";
  $exp_obj->send("uname -a #UNAME\n");
  $exp_obj->expect(4,
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
	[ timeout => sub { print STDERR "$hostname:\tError: running uname -a timed out, server may be running too slow\n"; } ],
	'-re', $Rover::user_prompt, );

  print "$hostname:\tWarning: unknown os type, running ALL and UNKNOWN commands\n" if $Rover::debug && $os_type eq 'UNKNOWN';
  $exp_obj->clear_accum();

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
        print "$hostname:\trunning $os_type ruleset '$_' on host '$hostname'\n" if $Rover::debug;
        eval "@{$Rover::rulesets{$_}}";

        if ( $@ ) {
          print STDERR "$hostname:\tError: ruleset encountered a fatal error: $@";
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
        print "$hostname:\trunning $subroutine($args_sub)\n" if $Rover::debug;
        $success = &$subroutine($args, $exp_obj, $hostname, $os_type);

        if (! $success) {
          $success = -4;
          print "$hostname:\tError: $subroutine($args_sub) failed\n" if $Rover::debug;
          $failed_commands++;
          last;
        }
      }
    }

    if ( $failed_commands ) {
      if ( $Rover::report_semaphore ) { $Rover::report_semaphore->down; };
      push(@Rover::report_failed_hosts,$hostname);
      $Rover::report_failed_runrules++;
      if ( $Rover::report_semaphore ) { $Rover::report_semaphore->up; };
      last;
    }
  }

  if ( ! $exp_obj <= 0 ) {
    $exp_obj->send("exit;\rexit;\rexit;\r");
    $exp_obj->soft_close();
    select(undef, undef, undef, 0.25);
  }

  if ( $Config{useithreads} && $Rover::use_threads ) {
    exit($success);
  } else {
    return($success);
  }
}

sub get_shell {
# Get expect object for shell access and/or root privilages
#
  my $hostname = shift;

  if ( ! @Rover::shell_access_routines ) {
    print STDERR "Error: No shell access routines specified, cannot continue\n";
    return(0);
  }

  my $exp_obj;
  foreach my $shell_access_routine (@Rover::shell_access_routines) {
   # Run each shell access routine, stop if one succeeds or no more routines left
   #
    print "\tDEBUG: $hostname: Attempting to gain shell access with routine $shell_access_routine\n" if $Rover::debug > 1;
    $exp_obj = &$shell_access_routine($hostname,$Rover::user,@Rover::user_credentials);

    if ( $exp_obj <= 0 ) {
      print "$hostname:\tWarning: shell access routine $shell_access_routine failed\n" if $Rover::debug > 1;
      if ( $exp_obj == 0 && $exp_obj == -1 ) { last; } # Dont continue if password or profile is wrong

    } else {
      last;
    }
  }

  if ( $exp_obj <= 0 ) {
   # Return code was an error, evaluate and increment appropriate counters
   #
    print STDERR "$hostname:\tError: could not gain shell on '$hostname'.\n";
    if ( $exp_obj == 0 ) {
      if ( $Rover::report_semaphore ) { $Rover::report_semaphore->down; };
      $Rover::report_failed_password++;
      if ( $Rover::report_semaphore ) { $Rover::report_semaphore->up; };

    } elsif ( $exp_obj == -1 ) {
      if ( $Rover::report_semaphore ) { $Rover::report_semaphore->down; };
      $Rover::report_failed_profile++;
      if ( $Rover::report_semaphore ) { $Rover::report_semaphore->up; };

    } elsif ( $exp_obj == -2 ) {
      if ( $Rover::report_semaphore ) { $Rover::report_semaphore->down; };
      $Rover::report_failed_network++;
      if ( $Rover::report_semaphore ) { $Rover::report_semaphore->up; };

    } elsif ( $exp_obj == -3 ) {
      if ( $Rover::report_semaphore ) { $Rover::report_semaphore->down; };
      $Rover::report_failed_root++;
      if ( $Rover::report_semaphore ) { $Rover::report_semaphore->up; };

    } else {
      print STDERR "$hostname:\tError: undefined return code from get_shell: $exp_obj, host: $hostname.\n";
    }

    if ( $Rover::report_semaphore ) { $Rover::report_semaphore->down; };
    push(@Rover::report_failed_hosts,$hostname);
    if ( $Rover::report_semaphore ) { $Rover::report_semaphore->up; };

   # Exit if this is a thread, return if it is not
    if ( $Config{useithreads} && $Rover::use_threads ) {
      exit($exp_obj);
    } else {
      return ($exp_obj);
    }
  }

  if ( $Rover::root_access_required ) {
    my $result = 0;
    foreach my $routine ( @Rover::root_shell_access_routines ) {
     # Iterate through any root shell access routines.  If we cant get root then increment
     # counters and return with error
     #
      print "\tDEBUG: $hostname: root_shell_access: attempting to get root with routine: '$routine'\n" if $Rover::debug > 1;
      $result = &$routine($exp_obj,$hostname);

      if ( $result ) { last; }
      print "$hostname:\tWarning: root access routine failed: '$routine'\n" if $Rover::debug > 1;
    }
    if ( ! $result ) {
      print "$hostname:\troot_access: FAILED to gain root access\n";

      if ( $Rover::report_semaphore ) { $Rover::report_semaphore->down; };
      $Rover::report_failed_root++;
      push(@Rover::report_failed_hosts, $hostname);
      if ( $Rover::report_semaphore ) { $Rover::report_semaphore->up; };

      $exp_obj->send("exit;\rexit;\rexit;\r");

      if (  $Config{useithreads} && $Rover::use_threads ) {
        exit(-3);
      } else {
        return(-3);
      }
    }
  }

  return($exp_obj);
}

1;
