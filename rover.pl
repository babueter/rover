#!/opt/freeware/bin/perl -I./modules -I./contrib
##!/usr/bin/perl -I./modules
#****************************************************************************
# Rover
#
#****************************************************************************
use Rover;
use Getopt::Std;

sub validate_opts {
# This function gathers the options passed to rover and configures the
# appropriate rover settings.
#
  my %get_opts;
  if ( ! getopts('H:c:f:l:tdDhv', \%get_opts) ) {
    usage();
    return(0);
  }

  if ($get_opts{h}) {
    usage();
    return(0);
  }

  if ($get_opts{H}) {
    $Rover::hosts_file = $get_opts{H};
  }

  if ($get_opts{c}) {
    $Rover::config_file = $get_opts{c};
  }

  if ($get_opts{l}) {
    $Rover::logs_dir = $get_opts{l};
  }

  if ($get_opts{f}) {
    $Rover::paralell_process_count = $get_opts{f};
  }

  if ($get_opts{t}) {
    $Rover::use_threads = 1;
  }

  if ($get_opts{d}) {
    $Rover::debug = 2;
  }

  if ($get_opts{D}) {
    $Expect::Log_Stdout = 1;
    $Expect::Exp_Internal = 1; 
    $Expect::Debug = 3;
    $Rover::paralell_process_count = 1;
  }

  return(1);
}

sub usage {
# Print a nice little help page regarding the command line usage
#
  print "Usage: rover.pl [-H file] [-c file] [-l dir] [-f n] [-FdDhV]\n";
  print "  -H file        File with a list of host names/ips. default is '$Rover::hosts_file'\n";
  print "  -c file        Rover commands file.  Default is $Rover::config_file.\n";
  print "  -l dir         Location of the logs directory.  All logs will be stored here.\n";
  print "  -f n           Use 'n' forks/threads in paralell for host processing\n";
  print "                 Default is $Rover::paralell_process_count.\n";
  print "  -t             Enable threads.  Default is to not use threads (Broken).\n";
  print "  -d             Debug output, sets $Rover::debug = 2\n";
  print "  -D             Verbose expect debug output, turns on Expect::Exp_Internal,\n";
  print "                 $Expect::Log_Stdout, and $Expect::Debug = 3.\n";
  print "  -h             Print this help message\n";
  print "\n";

  return(1);
}

sub report_completion_status {
# Print completion report
#
  my $count_failed_hosts = @Rover::report_failed_hosts;
  if ( $count_failed_hosts ) {
    my $total_hosts = @Rover::hosts_list;
    my $hosts_not_completed = $total_hosts - ($total_hosts - @Rover::report_failed_hosts);

    print "\n-------------------\n";
    print "   FAILURE COUNT\n";
    print "-------------------\n";
    print "Bad Passwords   : $Rover::report_failed_password\n";
    print "Root Failures   : $Rover::report_failed_root\n";
    print "Profile Errors  : $Rover::report_failed_profile\n";
    print "Network Errors  : $Rover::report_failed_network\n";
    print "Failed Rulesets : $Rover::report_failed_runrules\n";
    print "-------------------\n";
    print "Total: $count_failed_hosts\n";
    print "\n";
    if ( $hosts_not_completed != $count_failed_hosts ) {
      print "$hosts_not_completed Hosts not completed\n\n";
    }

    if ( $Rover::debug ) {
      print "Failed hosts:\n";
      foreach (@Rover::report_failed_hosts) { print "$_\n"; }
      print "\n";
    }
  } else {
    print "\nNo login failures recorded!\n\n";
  }

  return(1);
}

sub sigint_interrupt_handler {
  if ( $Config{useithreads} && $Rover::use_threads ) {


  } else {
    if ( $$ == $Rover::parent_id ) {
      system("stty echo") ;

      select(STDERR); $| = 1;     # make unbuffered
      select(STDOUT); $| = 1;     # make unbuffered

      my @keys = keys %Rover::global_process_current_host;
      if ( ! @keys ) { exit(0); }

      print "\nProcess interrupted, hosts in transit:\n";
      foreach my $key (@keys) {
        print "\tPID $key: ". $Rover::global_process_current_host{$key} ."\n";
        push (@Rover::report_failed_hosts, $Rover::global_process_current_host{$key});
      }

      if ( $Rover::debug ) {
        my $hosts_count = @Rover::global_process_completed_hosts;
        print "\n$hosts_count hosts completed successfully:\n";
        foreach my $host (@Rover::global_process_completed_hosts) {
          print "$host\n";
        }
      }

      my @children = keys %Rover::global_process_current_status;
      my $number_of_children = @children;
      my $killed_processes = kill('INT', @children);

      print "\n";
      print "$killed_processes processes terminated ($number_of_children total), waitnig for exit...";
      foreach (@children) {
        waitpid($_,0);
      }
      print "done\n";

      $Rover::report_failed_runrules += $number_of_children;
      report_completion_status();
    } else {
      exit(0);
    }

  }

  exit(0);
}

#****************************************************************************
# Begin main execution
#

$SIG{'INT'} = 'sigint_interrupt_handler';
$SIG{'TERM'} = 'sigint_interrupt_handler';
$SIG{'KILL'} = 'sigint_interrupt_handler';
$SIG{'HUP'} = 'IGNORE';

# Validate opts, override configuration variables
#
if ( ! validate_opts() ) {
  exit(-1);
}

# Read configuration file, store routines to execute
#
if ( ! build_config() ) {
  exit(-1);
}

# Gather user auth and privilage auth information
#
if ( ! read_authentication() ) {
  exit(-1);
}

# Start the real work, execute each process individually
#
process_hosts();

# All completed, report on findings.
#
report_completion_status();
