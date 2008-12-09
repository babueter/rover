#***************************************************************************
# Rover Package: 07/17/2007
# Author:        Bryan Bueter
#
#***************************************************************************
package Rover;
require 5.8.0;

our $VERSION = "3.0";

use Config;
use Expect;
use Carp;
use lib ("$ENV{HOME}/.rover/contrib");

use Rover::Shell_Routines;
use Rover::Host;
use Rover::Ruleset;

use threads;

use strict 'subs';
use strict 'vars';
use warnings;

our @OS_LIST = (
	'ALL',
	'AIX',
	'Darwin',
	'FreeBSD',
	'HP-UX',
	'IRIX',
	'Linux',
	'NetBSD',
	'OpenBSD',
	'SunOS',
	'Windows',
	'Unknown'
);

our @DEFAULT_LOGIN_METHODS = ("shell_by_ssh", "shell_by_telnet", "shell_by_rlogin" );
our @DEFAULT_FTP_METHODS = ("sftp", "ftp");
our @DEFAULT_ROOT_METHODS = ("get_root_by_su", "get_root_by_sudo");
our %DEFAULT = (
        _user => $ENV{'USER'},
        _user_prompt => '[>#\$] $',
        _user_prompt_force => '$ ',

        _user_credentials => undef,
        _root_credentials => undef,

        _host_objects => undef,
        _rulesets => undef,

        _login_methods => undef,
        _ftp_methods => undef,
        _root_methods => undef,

        _login_timeout => 7,
        _max_threads => 4,

        _registered_modules => undef,
        _registered_rules => undef,
        _registered_vars => undef,

        _lastrun_num_hosts => 0,
        _lastrun_num_succeed => 0,
        _lastrun_num_completed => 0,
        _lastrun_failed_password => 0,
        _lastrun_failed_profile => 0,
        _lastrun_failed_network => 0,
        _lastrun_failed_ruleset => 0,
        _lastrun_failed_getroot => 0,
        _lastrun_failed_hosts => undef,

        _config_file => "$ENV{HOME}/.rover/config",
        _logs_dir => "$ENV{HOME}/.rover/logs",
        _debug => 0,
);

sub new {
  my $class = shift;

  my $self = { } ;

  clear($self);
  register_module($self, "Rover::Core");
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
  printf ("%-15s\t%s\n", $hostname.":", $message) ;
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
  print "$message\n" if $self->debug == 2;
  carp "$message" if $self->debug > 2;
}

#***************************************************************************
# Settings
#***************************************************************************
sub load {
  my $self = shift;

 # Create new config if it doesnt exist
  if ( ! stat( $self->config_file ) ) {
    $self->pwarn("Warning: Creating new configuration\n");

    if ( ! stat( $ENV{'HOME'} ."/.rover" ) ) { mkdir $ENV{'HOME'} ."/.rover" ; }
    if ( ! stat( $self->logs_dir ) ) { mkdir $self->logs_dir; }
    $self->save;
  }

 # Config file and debug are the only option we want to save.
  my $old_config_file = $self->config_file();
  my $old_debug = $self->debug();
  $self->clear;
  $self->config_file($old_config_file);
  $self->debug($old_debug);

  $self->pdebug("DEBUG:\tOpening config file: ". $self->config_file ."\n");
  open(CONFIG, $self->config_file);
  my $conf_version = 0;
  my $conf_section = 0;
  my $rulesets_section = 0;
  my $modules_section = 0;

  my $current_module = "";
  my $current_module_hash = "";

  my $current_ruleset = "";
  my $ruleset_reading_description = 0;

  my $hosts_section = 0;
  my $current_host = "";

 # The actual readig of the config file
 #
  while (<CONFIG>) {
    chomp $_;
    my $line = $_;
    $line =~ s/^[ 	]*// ;

   # Determine if the section has changed
   #
    next if ! $line;
    if ( /^[ 	]*\[config\][ 	]*/ ) {
      $self->pdebug("DEBUG:\tEntering [config] section\n");
      $conf_section = 1;
      $modules_section = 0;
      $rulesets_section = 0;
      $hosts_section = 0;
      next;
    }
    if ( /^[ 	]*\[modules\][ 	]*/ ) {
      $self->pdebug("DEBUG:\tEntering [modules] section\n");
      $conf_section = 0;
      $modules_section = 1;
      $rulesets_section = 0;
      $hosts_section = 0;
      next;
    }
    if ( /^[ 	]*\[rulesets\][ 	]*/ ) {
      $self->pdebug("DEBUG:\tEntering [rulesets] section\n");
      $conf_section = 0;
      $modules_section = 0;
      $rulesets_section = 1;
      $hosts_section = 0;
      next;
    }
    if ( /^[ 	]*\[hosts\][ 	]*/ ) {
      $self->pdebug("DEBUG:\tEntering [hosts] section\n");
      $conf_section = 0;
      $modules_section = 0;
      $rulesets_section = 0;
      $hosts_section = 1;
      next;
    }

    my $option = (split(/[ 	]+/, $line))[0];
    my $value = $line;
    $value =~ s/^\S*[ 	]*// ;
    $value =~ s/[ 	]*$// ;
    $value =~ m/^[\'\"]?(.*?)[\'\"]?$/;
    $value = $1;

    if (!$conf_section && !$rulesets_section && !$hosts_section) {
     # General options are found here
     #

    }

    if ( $conf_section ) {
     # Rover configuration section
     #
      if ( $self->{"_".$option} && $value ) {
        if ( $value =~ m/^\(.*?\)$/ ) {
          $value =~ s/^\([ 	]*// ;
          $value =~ s/[ 	]*\)$// ;

          my @values = split(/ /, $value);
          $self->pdebug("DEBUG:\t\tStuffing array $option\n");
          $self->{"_".$option} = \@values;

        } else {
          $self->pdebug("DEBUG:\t\tSetting $option to value: $value");
          $self->{"_".$option} = $value;
        }
      }
    }

    if ( $modules_section ) {
     # Modules section
     #
      if (! $current_module && $line =~ m/^(.*)?:{$/) {
        $current_module = $1;
        $self->pdebug("DEBUG:\t\tRegistering module '$current_module'\n");
        $self->register_module($current_module) or croak;

      } elsif ( $current_module_hash && $line =~ m/^}$/ ) {
        $self->pdebug("DEBUG:\t\t\tClosing hash '$current_module_hash'");
        $current_module_hash = "";

      } elsif ( $current_module_hash && $value =~ m/^=> (.*)$/ ) {
        $value = $1;
        $option =~ m/^[\'\"]?(.*?)[\'\"]?$/;
        $option = $1;

        $self->pdebug("DEBUG:\t\t\tSetting hash $current_module_hash\{$option\} = $value\n");
	$$current_module_hash{$option} = $value;

      } elsif ( $value =~ m/^{$/ && $option =~ m/^\%(.*)$/ ) {
        $current_module_hash = $1;
        $self->pdebug("DEBUG:\t\t\tOpening hash '$current_module_hash'\n");

      } elsif ( $option =~ m/^[\$\@](.*)$/ ) {
        $option = $1;
        if ( $value =~ m/^\(.*?\)$/ ) {
          $value =~ s/^\([ 	]*// ;
          $value =~ s/[ 	]*\)$// ;

          my @values = split(/ /, $value);
          $self->pdebug("DEBUG:\t\t\tStuffing array: $option\n");
          @$option = @values;
        } else {
          $self->pdebug("DEBUG:\t\t\tSetting $option to value: $value\n");
          $$option = $value;
        }

      } elsif ( $current_module && $line =~ m/^};$/ ) {
        $self->pdebug("DEBUG:\t\tDone reading module '$current_module'\n");
        $current_module = "";
        
      } else {
        confess "Config error in line: $line\n";
      }
    }

    if ( $rulesets_section ) {
     # Ruleset definitions section
     #
      if (! $current_ruleset && $line =~ m/^(.*)?:$/) {
        $option = $1;
        $self->pdebug("DEBUG:\t\tAdding ruleset '$option'\n");
        $current_ruleset = $self->add_rulesets($option);
        $ruleset_reading_description = 1;

      } elsif ( $line =~ m/^{$/) {
        $ruleset_reading_description = 0;

      } elsif ( $ruleset_reading_description ) {
        my $tmp_description = "";
        if ( $current_ruleset->description ) {
          $tmp_description = $current_ruleset->description ."\n$line";
        } else {
          $tmp_description = $line;
        }
        $self->pdebug("DEBUG:\t\t\tDescription: $tmp_description\n");
        $current_ruleset->description($tmp_description);

      } elsif ( $option =~ m/^},/ && $value =~ /(.*)?;$/ ) {
        my @os_list = split(/ /, $1);
        $self->pdebug("DEBUG:\t\t\tSetting OS list: @os_list\n");
        $current_ruleset->os_list(@os_list);
        $current_ruleset = undef;

      } elsif ($current_ruleset) {
        $self->pdebug("DEBUG:\t\t\tAdding: $option($value)\n");
        $current_ruleset->add($option,$value);

      } else {
        confess "Config error in line: $line\n";
      }
    }

    if ( $hosts_section ) {
     # Hosts definition section
     #
      if (! $current_host && $line =~ m/^(.*)?:{$/) {
        $option = $1;
        $self->pdebug("DEBUG:\t\tAdding host $option\n");
        $self->add_hosts($option) || confess "Error adding host '$option'\n";
        $current_host = $self->host($option);

      } elsif ( $option =~ m/^};$/ ) {
        $self->pdebug("DEBUG:\t\tDone reading host: $current_host\n");
        $current_host = undef;

      } elsif ($current_host) {
        if ( $value =~ m/^\(.*?\)$/ ) {
          $value =~ s/^\([ 	]*// ;
          $value =~ s/[ 	]*\)$// ;

          my @values = split(/ /, $value);
          $self->pdebug("DEBUG:\t\t\tStuffing array: $option\n");
          $current_host->{"_".$option} = \@values;

        } else {
          $self->pdebug("DEBUG:\t\t\tSetting host option $option = $value\n");
          $current_host->{"_".$option} = $value;
        }
      } else {
        confess "Config error in line: $line\n";
      }
    }

  }
  close(CONFIG);

  if ( ! stat($self->logs_dir()) ) {
    mkdir $self->logs_dir or die "Error: Cannot create logs dir: ". $self->logs_dir ."\n";
  }
}

sub save {
  my $self = shift;

 # Write general configuration section
 #
  open(CONFIG,">".$self->config_file);
  print CONFIG "version ". $self->VERSION ."\n";
  print CONFIG "\n";
  print CONFIG "[config]\n";
  print CONFIG "user ", $self->user ."\n";
  print CONFIG "user_prompt '". $self->user_prompt ."'\n";
  print CONFIG "user_prompt_force '". $self->user_prompt_force ."'\n";
  print CONFIG "\n";
  print CONFIG "debug ". $self->debug ."\n";
  print CONFIG "logs_dir '". $self->logs_dir ."'\n";
  print CONFIG "max_threads ". $self->max_threads ."\n";
  print CONFIG "login_timeout ". $self->login_timeout ."\n";
  print CONFIG "login_methods ( ";
  my @tmp_login_methods = $self->login_methods;
  print CONFIG "@tmp_login_methods )\n";
  print CONFIG "ftp_methods ( ";
  my @tmp_ftp_methods = $self->ftp_methods;
  print CONFIG "@tmp_ftp_methods )\n";
  print CONFIG "\n";

 # Write module information
 #
  print CONFIG "[modules]\n";
  foreach my $module ($self->registered_modules) {
    print CONFIG "$module:{\n";
    foreach my $module_var ($self->registered_vars($module)) {
      if ( $module_var =~ m/^\$(.*)$/ ) {
        $module_var = $1;
        print CONFIG "\t\$$module_var ". $$module_var ."\n";

      } elsif ( $module_var =~ m/^\@(.*)$/ ) {
        $module_var = $1;
        my @tmp_array = @$module_var;
        print CONFIG "\t\@$module_var ( @tmp_array )\n";

      } elsif ( $module_var =~ m/^\%(.*)$/ ) {
        $module_var = $1;
        print CONFIG "\t\%$module_var {\n";
        foreach my $module_var_key (keys %$module_var) {
          print CONFIG "\t\t'$module_var_key' => ". $$module_var{$module_var_key} ."\n";
        }
        print CONFIG "\t}\n";

      } else {
        $self->pwarn("Warning: unknown variable type for '$module_var', skipping");
      }
    }
    print CONFIG "};\n";
    print CONFIG "\n";
  }

 # Write ruleset information
 #
  print CONFIG "[rulesets]\n";
  foreach my $ruleset ($self->ruleset) {
    print CONFIG "$ruleset:\n";
    print CONFIG $self->ruleset($ruleset)->description ."\n" if $self->ruleset($ruleset)->description;
    print CONFIG "{\n";
    foreach my $command ($self->ruleset($ruleset)->commands) {
      print CONFIG "\t$command->[0]\t$command->[1]\n";
    }
    print CONFIG "}, ";
    my @os_list = $self->ruleset($ruleset)->os_list;
    print CONFIG "@os_list ;\n";
    print CONFIG "\n";
  }
  print CONFIG "\n";

 # Write hosts information
 #
  print CONFIG "[hosts]\n";
  foreach my $hostname ($self->host) {
    print CONFIG $hostname .":{\n";
    print CONFIG "\tos ". $self->host($hostname)->os ."\n" if $self->host($hostname)->os;
    print CONFIG "\tusername ". $self->host($hostname)->username ."\n" if $self->host($hostname)->username;
    print CONFIG "\tdescription '". $self->host($hostname)->description ."'\n" if $self->host($hostname)->description;
    if ( $self->host($hostname)->login_methods ) {
      print CONFIG "\tlogin_methods ( ";
      my @tmp_login_methods = $self->host($hostname)->login_methods;
      print CONFIG "@tmp_login_methods )\n";
    }
    if ( $self->host($hostname)->ftp_methods ) {
      print CONFIG "\tftp_methods ( ";
      my @tmp_ftp_methods = $self->host($hostname)->ftp_methods;
      print CONFIG "@tmp_ftp_methods )\n";
    }
    print CONFIG "};\n";
    print CONFIG "\n";
  }
  print CONFIG "\n";
  close(CONFIG);
}

sub clear {
  my $self = shift;

  my @user_credentials = ();
  %{$self} = %DEFAULT;

 # Set up anonymous references
 #
  $self->{_user_credentials} = [( )];
  $self->{_root_credentials} = [( )];
  $self->{_host_objects} = { };
  $self->{_rulests} = { };
  $self->{_login_methods} = [( @DEFAULT_LOGIN_METHODS )];
  $self->{_ftp_methods} = [( @DEFAULT_FTP_METHODS )];
  $self->{_root_methods} = [( @DEFAULT_ROOT_METHODS )];
  $self->{_registered_modules} = { };
  $self->{_registered_rules} = { };
  $self->{_registered_vars} = { };
  $self->{_lastrun_failed_hosts} = [( )];

  register_module($self, "Rover::Core");
}

sub user {
  my ($self, $user) = @_;

  $self->{_user} = $user if defined($user);
  return $self->{_user};
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

sub user_credentials {
  my $self = shift;
  my @user_credentials = @_;

  $self->{_user_credentials} = \@user_credentials if @user_credentials;
  return @{$self->{_user_credentials}};
}

sub root_credentials {
  my $self = shift;
  my @root_credentials = @_;

  $self->{_root_credentials} = \@root_credentials if @root_credentials;
  return @{$self->{_root_credentials}};
}

sub config_file {
  my ($self, $config_file) = @_;

  $self->{_config_file} = $config_file if defined($config_file);
  return $self->{_config_file};
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

sub root_methods {
  my $self = shift;
  my @root_methods = @_;

  $self->{_root_methods} = \@root_methods if @root_methods;
  return @{$self->{_root_methods}};
}

sub ftp_methods {
  my $self = shift;
  my @ftp_methods = @_;

  $self->{_ftp_methods} = \@ftp_methods if @ftp_methods;
  return @{$self->{_ftp_methods}};
}

sub login_timeout {
  my ($self, $login_timeout) = @_;

  $self->{_login_timeout} = $login_timeout if defined($login_timeout);
  return $self->{_login_timeout};
}

sub debug {
  my ($self, $debug) = @_;

  $self->{_debug} = $debug if defined($debug);
  return $self->{_debug};
}

#***************************************************************************
# Thread settings
#***************************************************************************
sub max_threads {
  my ($self, $max_threads) = @_;

  $self->{_max_threads} = $max_threads if defined($max_threads);
  return $self->{_max_threads};
}

#***************************************************************************
# Host routines
#***************************************************************************
sub add_hosts {
  my $self = shift;
  my @hosts = @_;

  my $host_count = 0;
  foreach my $host (@hosts) {
    if (! gethostbyname($host) ) {
      $self->pwarn("Warning: Unable to resolve hostname/address: $host, server will not be included\n");
      next;
    }
    $self->pdebug("DEBUG:$host:\tCreating host object");

    if ( $self->host($host) ) {
      $self->pwarn("Warning: attempting to add duplicate host '$host'\n");
      next;
    }
    $self->host($host, new Rover::Host($host, "Unknown", $self->user(), $self->user_credentials()))
	or $self->perror("Error: Unable to create host object for $host\n");
    $host_count++ if $self->host($host);
  }

  return($host_count);
}

sub del_hosts {
  my $self = shift;
  my @hosts = @_;

  my $host_count = 0;
  foreach my $host (@hosts) {
    if ( ! defined($self->{_host_objects}->{$host}) ) {
      $self->pwarn("Warning: delete host failed, '$host' doesnt exist\n");
      next;
    }
    delete $self->{_host_objects}->{$host};
    $host_count++;
  }

  return($host_count);
}

sub host {
  my ($self, $host, $obj) = @_;

  return keys(%{$self->{_host_objects}}) if ! $host;

 # Atempting to recall a host that was not added
 #
  if ( ! defined($self->{_host_objects}->{$host}) && ! defined($obj)  ) {
    return 0;
  }

  $self->{_host_objects}->{$host} = $obj if defined($obj);
  return $self->{_host_objects}->{$host};
}

sub login {
  my $self = shift;
  my @hosts = @_;

  if ( ! @hosts ) {
    @hosts = $self->host();
  }

  my $successful_login_count = 0;
  my $return;
  foreach my $host ( @hosts ) {
    my $host_obj = $self->host($host);

    $self->pdebug("DEBUG:\tGetting shell for $host (". $host_obj->hostname() .")\n");

    if ( $host_obj->shell() > 0 ) {
      my $result = 0;
      eval {
        $self->pdebug("DEBUG:\tShell already defined, checking status\n");
        $host_obj->shell->clear_accum();
        $host_obj->shell->send("#TEST \n");
        $result = $host_obj->shell->expect(4, '-re', $self->user_prompt);
      };
      if ( ! $result ) {
        $self->pdebug("DEBUG:\t\tShell object failed with error, resetting to null\n");
        $host_obj->shell( 0 );
      }
    }

    if ( $host_obj->shell() <= 0 ) {
      my @login_methods = $self->login_methods();
      @login_methods = $host_obj->login_methods if $host_obj->login_methods;
      $self->pdebug("DEBUG:\tWill attempt the following methods: @login_methods\n");

     # If we encounter a failed profile or bad password, dont continue with other methods.
     #
      foreach my $method ( @login_methods ) {
        $return = $self->$method($host);
        $self->pdebug("DEBUG:\t\tLogin method '$method' for host '$host' returned failure: $return\n") if $return < 0;
        last if $return > -3;
      }
    }

    if ( $host_obj->shell() <= 0 ) {
     # -3 = failed network, -2 = failed profile, -1 = failed password
      if ( $return == -1 ) {
        $self->pinfo($host, "Bad Password");

      } elsif ( $return == -2 ) {
        $self->pinfo($host, "Failed Profile");

      } elsif ( $return == -3 ) {
        $self->pinfo($host, "Network Failure");

      } else {
        $self->pinfo($host, "Unknown login error: $return");
      }
      $self->pwarn("Warning: Unable to get shell for host $host\n");

    } else {
     # Determine OS type and store results
     #
      my $os_type = "";
      $host_obj->shell->send("uname -a #UNAME\n");
      $host_obj->shell->expect(4,
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
          [ timeout => sub { $self->pwarn($host_obj->hostname .":\tWarning: uname -a timed out, server may be running too slow\n"); } ],
          '-re', $self->user_prompt, );
  
      $host_obj->shell->clear_accum();

      $host_obj->os($os_type);
      $self->pwarn($host_obj->hostname .":\tWarning: unknown os type, running ALL and Unknown commands\n") if $os_type eq 'Unknown';
    }
    $successful_login_count++ if $host_obj->shell() > 0;
  }

  if ( @hosts == 1 ) {
    return($return);
  }
  return($successful_login_count);
}

sub ftp_login {
  my $self = shift;
  my @hosts = @_;

  if ( ! @hosts ) {
    @hosts = $self->host();
  }

  my $successful_login_count = 0;
  my $return;
  foreach my $host ( @hosts ) {
    my $host_obj = $self->host($host);

    $self->pdebug("DEBUG:\t\tGetting FTP shell for $host (". $host_obj->hostname() .")\n");

   # We're not going to test the FTP object, its just safer to open a new one
    my $ftp_method = Rover::Core::FTP::determine_ftp_method( $host_obj, "setup" );
    if ( ! $ftp_method ) {
      $return = 0;
      next;
    }

   # After finding the ftp_method to use, run it and capture the status
    $self->pdebug("DEBUG:\t\tSetting up FTP object for ". $host_obj->hostname ." using $ftp_method\n");
    $return = &$ftp_method($self, $host);

   # Return 0 if failed, set up log file if success
    if ( $return <= 0 ) {
      $self->pdebug("DEBUG:\t\tFailed getting FTP object for '$host', return code '$return'\n");
      $return = 0;
      next;
    }
    if ( $host_obj->ftp_method_used() eq "sftp" ) {
      $host_obj->ftp->log_file($self->logs_dir() ."/$host.log");
    }
    $successful_login_count++;
    $return = 1;
  }

  if ( @hosts == 1 ) {
    return($return);
  }
  return($successful_login_count);
}

sub getroot {
  my $self = shift;
  my @hosts = @_;

  if ( ! @hosts ) {
    @hosts = $self->host();
  }

  my $successfull_root_count = 0;
  my $return;
  foreach my $host ( @hosts ) {
    my $host_obj = $self->host($host);

    $self->pdebug("DEBUG:\tGetting root for $host (". $host_obj->hostname() .")\n");
    if ( $host_obj->shell > 0 ) {
      foreach my $method ( $self->root_methods() ) {
        $return = $self->$method($host);
        $self->pdebug("DEBUG:\t\tGetroot method '$method' for host '$host' returned failure: $return\n") if ! $return ;
        last if $return;
      }

      if ( $return ) {
        $successfull_root_count++;
      } else {
        $host_obj->shell()->hard_close();
      }
    } else {
      $host_obj->shell()->hard_close();
      $self->pwarn("Warning: Get root failed for '$host', not logged in\n");
    }
  }

  if ( @hosts == 1 ) {
    return($return);
  }
  return($successfull_root_count);
}

#***************************************************************************
# Module routines
#***************************************************************************
sub register_module {
  my ($self, $module_name) = @_;

  return (0) if ! $module_name;

  my $module_load = "use $module_name;" ;
  eval $module_load ;
  if ( $@ ) {
    perror($self, "Unable to load module '$module_name': $@\n");
    return 0;
  }

  import $module_name;

  my $module_export = $module_name ."::EXPORT";
  my $module_vars = $module_name ."::ROVER_VARS";
  my $module_desc = $module_name ."::DESCRIPTION";

  my $module_desc_text = "";
  $module_desc_text = $$module_desc if defined($$module_desc) ;

  my @registered_rules = @$module_export ;
  my @registered_vars = @$module_vars ;

  $self->{_registered_modules}->{$module_name} = $module_desc_text;
  $self->{_registered_rules}->{$module_name} = \@registered_rules;
  $self->{_registered_vars}->{$module_name} = \@registered_vars;
}

sub unregister_module {
  my ($self, $module_name) = @_;

  delete $self->{_registered_modules}->{$module_name};
  delete $self->{_registered_rules}->{$module_name};
  delete $self->{_registered_vars}->{$module_name};
}

sub registered_modules {
  my ($self, $module) = @_;

  if ( defined($module) ) {
    return 1 if defined($self->{_registered_modules}->{$module});
  } else {
    return keys %{$self->{_registered_modules}};
  }
}

sub module_description {
  my ($self, $module) = @_;

  return $self->{_registered_modules}->{$module} if $self->{_registered_modules}->{$module};
  return undef;
}

sub registered_rules {
  my ($self, $module) = @_;

  if ( defined($module) ) {
    return @{$self->{_registered_rules}->{$module}} if $self->{_registered_rules}->{$module} ;
  } else {
    my %registered_rules = %{$self->{_registered_rules}} ;
    return \%registered_rules;
  }
  return undef;
}

sub registered_vars {
  my ($self, $module) = @_;

  if ( defined($module) ) {
    return @{$self->{_registered_vars}->{$module}} if $self->{_registered_vars}->{$module} ;
  } else {
    my %registered_vars = %{$self->{_registered_vars}} ;
    return \%registered_vars;
  }
  return ;
}

#***************************************************************************
# Ruleset routines
#***************************************************************************
sub add_rulesets {
  my $self = shift;
  my @rulesets = @_;

  my $count = 0;
  my @added_rulesets = ();
  foreach my $ruleset (@rulesets) {
    if ( defined($self->{_rulesets}->{$ruleset}) ) {
      $self->pwarn("Cannot add ruleset '$ruleset' as it already exists.  skipping.\n");
      next;
    }
    $self->{_rulesets}->{$ruleset} = new Rover::Ruleset;
    push(@added_rulesets, $self->{_rulesets}->{$ruleset});
    $count++;
  }

  if ( $count == 1 ) {
    return($added_rulesets[0]);

  } elsif ( $count > 2 ) {
    return(\@added_rulesets);
  }

  return($count);
}

sub del_rulesets {
  my $self = shift;
  my @rulesets = @_;

  my $count = 0;
  foreach my $ruleset (@rulesets) {
    if ( ! defined($self->{_rulesets}->{$ruleset}) ) {
      $self->pwarn("Ruleset '$ruleset' does not exist.  skipping\n");
      next;
    }
    delete $self->{_rulesets}->{$ruleset};
    $count++;
  }
  return($count);
}

sub ruleset {
  my ($self, $ruleset) = @_;

  return keys( %{$self->{_rulesets}} ) if ! defined($ruleset);

  if ( ! defined($self->{_rulesets}->{$ruleset}) ) {
    return undef;
  }
  return( $self->{_rulesets}->{$ruleset} );
}

sub run_rulesets {
 # Subroutine to run a list of rulesets against all hosts.  We use threading
 # to process more then one host at a time.
 #
  my $self = shift;
  my @rulesets = @_;

  my $args = pop @rulesets if ref($rulesets[-1]) eq "HASH" ;

  my @verified_rulesets = ();
  foreach my $ruleset (@rulesets) {
   # Verify all rulesets exist, run only those that do
   #
    if ( $self->ruleset($ruleset) ) {
      push(@verified_rulesets, $ruleset);
    } else {
      $self->pwarn("Warning: Ruleset '$ruleset' does not exist, excluding from the list\n");
    }
  }
  @rulesets = @verified_rulesets;

  if ( ! @rulesets ) {
    $self->perror("Error: No rulesets to run\n");
    return(0);
  }

  my $max_threads = $self->max_threads();
  my @thread_ids = ();

  my @hosts = $self->host();
  my @threaded_hosts = ();

  my $get_root = 0;
  my $hangup = 1;

 # Read arguments from passed hashref
 #
  if ( defined( $args->{'Threads'} ) ) {
    $max_threads = $args->{'Threads'};

    if ( ! $max_threads =~ m/^-?\d+$/ ) {
      $self->perror("Error: Threads value not an integer\n");
      return(0);
    }
  }
  if ( defined( $args->{'Hosts'} ) ) {
    @hosts = ();
    if ( ref( $args->{'Hosts'} ) ne 'ARRAY' ) {
      $self->perror("Error: Hosts value not an array\n");
      return(0);
    }
    foreach my $host (@{ $args->{'Hosts'} }) {
      if ( $self->host($host) ) { push(@hosts, $host); }
    }

    if ( ! @hosts ) {
      $self->perror("Error: No valid hosts selected\n");
      return(0);
    }
  }
  if ( defined( $args->{'Root'} ) ) {
    $get_root = $args->{'Root'} ;
  }

  $self->clear_run_status();
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
    $self->pinfo($host, "Logging in");
    my $result = $self->login($host);
    if ( $result > 0 ) {

     # Determine if we need an FTP object from our list of rulesets.  If we do,
     # setup the ftp object first because that portion is not thread safe
     #
      my $need_ftp = 0;
      foreach my $ruleset_name ( @rulesets ) {
        my $ruleset = $self->ruleset($ruleset_name);

        if ( grep( /^[gp][eu]t_file/, $ruleset->list()) ) {
          $result = $self->ftp_login($host);
          last;
        }
      }
      if ( $result > 0 ) {
        $self->pdebug("DEBUG:\tAdding $host to threaded list\n");
        push(@threaded_hosts, $host);
      }
    }

    if ( $result <= 0 ) {
      $results[$result]++;
      push(@failed_hosts, $host);

      $self->{_lastrun_num_completed}++;
    }

   # Our list is maxed out, we can now run our ruleset(s) with threads
   #
    if ( @threaded_hosts == $max_threads || ! @hosts ) {
      $self->pdebug("DEBUG:\tThreading for hosts: @threaded_hosts\n");
      if ( ! @hosts ) { $max_threads = @threaded_hosts }

      for (my $t=0; $t<$max_threads; $t++) {
        my $host_obj = $self->host($threaded_hosts[$t]);
        next if ! $host_obj->shell();

        $self->pdebug("DEBUG:\t\tThreading host ". $host_obj->hostname .", thead id $t\n");
        $thread_ids[$t] = threads->new("exec_thread", $self, $host_obj->hostname, $get_root, @rulesets);
      }

      for (my $t=0; $t<$max_threads; $t++) {
        $self->pdebug("DEBUG:\t\tJoining thread id $t\n");
        my $result = $thread_ids[$t]->join();

        if ( ! $result ) {
          $self->pdebug("DEBUG:\tReturned bad status ($result) for thread id $t ($threaded_hosts[$t])\n");
          if ( $result == -4 ) {
            $results[$result]++;
            push(@failed_hosts, $threaded_hosts[$t]);

            $self->pinfo($threaded_hosts[$t], "Getroot Failure\n");

          } else {
            $results[1]++;
            push(@failed_hosts, $threaded_hosts[$t]);

            $self->pinfo($threaded_hosts[$t], "Failed Ruleset\n");
          }
        } else {
          $results[0]++;
	  $self->pinfo($threaded_hosts[$t], "Done\n");
        }
        $self->{_lastrun_num_completed}++;
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

  $self->pdebug("DEBUG:\tFinished, completed hosts: ". $self->{_lastrun_num_completed} ."\n");
  return($results[0]);
}

sub exec_thread {
  my $rover = shift;
  my $host = shift;
  my $get_root = shift;
  my @rulesets = @_;

  my $host_obj = $rover->host($host);

 # Get root if needed
 #
  my $result = 1;
  if ( $get_root ) {
    $rover->pinfo($host, "Getting root");
    $rover->pdebug("DEBUG:\tAttempting to get root for $host\n");
    my $root_result = $rover->getroot($host);
    if ( ! $root_result ) {
      $result=-4;
      $rover->pdebug("DEBUG:\t\tFailure getting root for $host\n");

      return($result);
    }
  }

  foreach my $ruleset ( @rulesets ) {
   # Run each ruleset making sure the os of the host matches the os_list of the ruleset
   #
    $rover->pdebug("DEBUG:\tRunning ruleset '$ruleset' on host '$host'\n");
    my $ruleset_obj = $rover->ruleset($ruleset);

    my $host_os = $host_obj->os;
    if ( $ruleset_obj->os_list() ) {
      if ( ! grep(/^$host_os$/, $ruleset_obj->os_list()) && ! grep(/^ALL$/, $ruleset_obj->os_list()) ) {
        my @os_list = $ruleset_obj->os_list();
        $rover->pdebug("DEBUG:\t\tSkipping '$ruleset' for OS $host_os (@os_list)\n");
        next;
      }
    }

    foreach my $ruleset_command ( $ruleset_obj->commands ) {
      $rover->pdebug("DEBUG:\t\tRunning ruleset command on '$host': @{$ruleset_command}\n");

      my $command = $ruleset_command->[0];
      my $args = $ruleset_command->[1];

      $result = $rover->$command($host, $args);
      last if ! $result;
    }
    last if ! $result;
  }

  if ( $result ) {
    $rover->pdebug("DEBUG:\t\tRuleset success, soft_closing object\n");
    $host_obj->soft_close();

  } else {
    $rover->pdebug("DEBUG:\t\tRuleset failure, hard_closing object\n");
    $host_obj->hard_close();

  }
  return($result);
}

sub clear_run_status {
  my $self = shift;

  $self->{_lastrun_num_hosts} = 0;
  $self->{_lastrun_num_succeed} = 0;
  $self->{_lastrun_num_completed} = 0;
  $self->{_lastrun_failed_password} = 0;
  $self->{_lastrun_failed_profile} = 0;
  $self->{_lastrun_failed_network} = 0;
  $self->{_lastrun_failed_ruleset} = 0;
  $self->{_lastrun_failed_getroot} = 0;

  $self->{_lastrun_failed_host} = [()];
}

sub run_status {
  my $self = shift;

  my %results;
  my @failed_hosts = @{$self->{_lastrun_failed_hosts}};

  $results{num_hosts} = $self->{_lastrun_num_hosts};
  $results{num_succeed} = $self->{_lastrun_num_succeed};
  $results{num_completed} = $self->{_lastrun_num_completed};
  $results{failed_password} = $self->{_lastrun_failed_password};
  $results{failed_profile} = $self->{_lastrun_failed_profile};
  $results{failed_network} = $self->{_lastrun_failed_network};
  $results{failed_ruleset} = $self->{_lastrun_failed_ruleset};
  $results{failed_getroot} = $self->{_lastrun_failed_getroot};
  $results{failed_hosts} = \@failed_hosts;

  return(%results);
}

END {

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
  $r->add_rulesets("Ruleset 1");
  my $ruleset = $r->ruleset("Ruleset 1");

  $ruleset->add("execute", "uptime");
  $ruleset->add("execute", "who");
  $ruleset->add("get_file", "/etc/motd");
  $r->run_rulesets("Ruleset 1");

  # Run as root
  $r->run_rulesets("Ruleset 1", {"Root" => 1});

  # Method #2, login and run the commands in serial
  $r->login("host1");
  $r->execute("host1", "uptime");
  $r->execute("host1", "who");
  $r->get_file("host1", "/etc/motd");

  # Close the host objects when we are done (not needed for method 1)
  $r->host("host1")->soft_close();

  # Or avoid actually logging out and just kill the sessions
  $r->host("host1")->hard_close();

  # Save and load the configuration file
  $r->load();
  $r->save();

  # Change the location of the config file
  $r->config_file("/tmp/rover_config");

  # Reset to the default configuration
  $r->clear();


=head1 DESCRIPTION

Rover is a wrapper of the Expect for perl module.  It aids in
managing SSH, Telnet, Rlogin, and SFTP/FTP connections to remote hosts,
enabling you to execute commands, transfer files, change passwords, et al,
without having to manage the login process.

=head1 USAGE

=over 4

=head2 LOADING ROVER

=item new Rover ()

Create a new Rover object.

=item $r->load()

Load the saved Rover configuration.  The default location is
$HOME/.rover/config.  If this does not exist, this call will create
it for you.

=item $r->save()

Save the configuration to file.  If the current config file does not
exist, this will create it for you.

=item $r->clear()

Reset all options to their defaults.

=head2 GENERAL CONFIGURATION

=item $r->config_file( $filename )

Change the location of the Rover configuration file.  The default
value is $HOME/.rover/config.

=item $r->logs_dir( $dir | undef )

Set or return the directory where all the Expect logs are stored.  This defaults
to "$ENV{USER}/.rover/logs".

=item $r->user( $username | undef )

Set or return the username to be used in the login process.  The default
value is $ENV{USER}.

=item $r->user_credentials( @passwords | undef )

Set or return the password list to be used in the login process.  By default
there is no value.

=item $r->root_credentials( @passwords | undef )

Set or return the password list to be used in the getroot process.  By default
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

=item $r->login_methods( @methods | undef )

Set or return the login methods.  Default values are: shell_by_ssh, shell_by_telnet,
shell_by_rlogin.  You must reference a valid shell method, the default values contain
all of the available methods that come with Rover.

=item $r->ftp_methods( @methods | undef )

Set or return the file transfer protocol methods.  Default values are: sftp, ftp, rcp.
These are the only file transfer methods packaged with Rover.

=item $r->ftp_methods( @methods | undef )

Set or return the getroot methods.  Default values are: get_root_by_su, get_root_by_sudo.
These methods are supplied with the default installation of Rover.

=item $r->login_timeout( $seconds | undef )

Set or return the timeout value used in the Expect block during login.  This defaults
to 5 seconds.

=item $r->max_threads( $count | undef )

Set or return the maximum number of threads to use in parallel.  The default is 4.

=item $r->debug( $debug | undef )

Set or return the debug level.  Values are 0 = Only fatal errors, 1 = Warnings and
informational messages, 2 = debuging output.  The default value is 0.

=head2 HOST CONFIGURATION

=item $r->add_hosts( @hosts )

Add a list of hosts to the rover section.  This creates a Rover::Host object
for each host in the list and makes them available via the $r->host
method.  The hosts in the array passed to this routine are either IP addresses
or host names that must resolve to an address.  That is also the identifier
used to recall the host object.

The return value for this function is the number of successfull hosts that
where added.

=item $r->del_hosts( @hosts )

Delete a host, or list of hosts from the rover config.  The return value is the
number of successfull hosts deleted from Rover.

=item $r->host( $hostname | undef )

Return the host object referenced by "hostname".  This is a reference to
the Rover::Host object used by Rover.  If no hostname is provided, an
array is returned with a list of the hostnames available.

=head2 RULESET CONFIGURATION

=item $r->add_rulesets( @rulesets )

Add a list of rulesets to rover.  This creates a Rover::Ruleset object
for each ruleset in the list and makes them available via the $r->ruleset
method.  The array should contain scalar names for each ruleset you
want to add.  The number of rulesets created is the return value.

=item $r->del_rulesets( @ruleets )

Deletes the rulesets from the rover object, and from memory.  The number
of rulesets deleted is the return value.

=item $r->ruleset( $ruleset | undef )

Return the ruleset object referenced by $ruleset.  This is a reference to
the Rover::Ruleset object used by Rover.  If no ruleset is provided, an
array is returned with a list of rulesets available.

=head2 RUNNING ROVER

=item $r->run_rulesets( @rulesets, { option => value, [...]} )

Run, in parallel, a list of Rulesets on all, or a subset of hosts stored
in the Rover object.  This process uses threading to login to each host,
set up an Expect object, execute each ruleset, and logout.  The optional
list of hosts is the first argument, if that value is null, all hosts
are used.

The number of concurrent threads is determined by $r->max_threads.

Results are stored within the Rover object.  They can be recalled using
the $r->run_status() routine.

Options can be passed through a hash reference after the list of rulesets.
Thise options are as follows:

  Hosts => \@host_list

=over 8

Instead of running on all hosts, run on a subset of hosts stored in the
array reference.

=back

  Root => bool

=over 8

Wether or not to run as root.  This will prompt run_ruleses to execute
$r->getroot() on each host after threading has started.  The default
is to not run as root.

=back

  Threads => integer

=over 8

Number of threads to run in parallel.  The default is to use $r->max_threads()
value.

=back

Examples of running rulesets are as follows:

  $r->run_rulesets(@rulesets);

This will run all rulesets in the array @rulesets on all hosts stored in Rover.
It will not attempt to gain root access, and it will use $r->max_threads() to
determine the number of threads to run in parallel.

  $r->run_rulesets(@rulesets, { 'Hosts' => \@hosts, 'Root' => 1 });

This will run rulesets stroed in @rulesets array, on hosts stored in the \@hosts
array.  This will attempt to gain root access on the hosts.

=item $r->login( @hosts | undef )

Logs into each host specified in @hosts and sets up the Expect object.
The @hosts parameter is optional, the default action is to log into
all hosts stored in the Rover object.

This function is not threaded, and could take a long time to run for
more then 20 or so hosts.  If your using the $r->run_rulesets()
routine, you do not need to run this first.

If this is ran against more then one host, the total number of successfull
logins is returned.  If this is run against one host, the expect object
is returned, or the error code.  Error codes are as follows:

  >0  The actual Expect object
   0  Unknown error
  -1  Bad password
  -2  Profile error, unrecognized prompt
  -3  Network error or timeout

=item $r->ftp_login( @hosts | undef )

Attempts to set up a file transfer Expect object each host in @hosts.  This
reads values from $r->ftp_methods array to determine what methods are
available.  FTP methods are supplied with the Rover::Core module.  They
are as follows:

  sftp   The system "sftp" command.
  ftp    Log in with Net::FTP perl module

The Expect object is then stored in the Rover host object, and can be
referenced with: $r->host( "hostname" )->ftp()

If this is run against more then one host, the total number of successfull
logins is returned.  If this is run against one host, the expect object
is returned, or the error code.  Error codes are the same as $r->login()
error codes (see above).

=item $r->getroot( @hosts | undef )

Gains root on each host specified in @hosts.  The @hosts parameter is
optional, the default action is to log into all hosts stored in the Rover
object.  It is expected that each host already has an expect object set
up.

This attempts to gain root access by using each method in $r->root_methods()
array.  These methods are supplied by the Rover::Shell_Routines module
and are as follows:

  get_root_by_su    Attempt to su to root.
  get_root_by_sudo  Use sudo to get root

For the su attempt, $r->root_credentials is used for passwords to the su
command.  This will fail if no passwords are supplied.

For the sudo attempt, $r->user_credentials is used for passwords.  This
will attempt to sudo even if this list is empty.

If this is run against more then one host, the total number of successfull
attempts are returned.  If this is run against one host, success or failure
is returned.

=item $r->run_status()

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

=head2 LOADING MODULES

Rover is shipped with one module, Rover::Core.  It is loaded by default.  This module
adds the default rules for creating ruleset.  They include:

  execute     Execute a command and wait for the prompt
  send        Send a command, do not wait for the prompt
  put_file    Transfer a local file to the remote host
  get_file    Transfer a file from the remote host

See the WRITING MODULES section for details on adding functionality to Rover.

=item $r->register_module( $perlmodname )

Register a module by package name.  For example, "Rover::Core" comes with Rover, and is
registered by default.  You must have the perl module file in your @INC path.
Rover adds /usr/share/rover/contrib, /usr/local/share/rover/contrib, and 
$HOME/.rover/contrib to @INC at startup.  All registered modules are saved when
calling $r->save().  They will then be loaded automatically when calling $r->load().

=item $r->unregister_module( $perlmodname )

Unregister module by package name. This removes the reference to the module from
Rover, and issues the command "no $perlmodname".

=item $r->registered_modules( $perlmodname | undef )

Simple method to return a list of registered modules.  If you specify a module
name, it will return true if the module is registered, false if it is not.

=item $r->module_description( $perlmodname )

Return the text description of the module.

=item $r->registered_rules( $perlmodname | undef )

Return the list of exported rules for a specific module.

If no module is specified, the return value is a hash of all the rules exported
by each module.  The keys of the hash are the module name, the value is a
reference to a list of the exported rules.

For example, to get the list of exported rules for "Rover::Core", you would
issue one of the following:

  @array = $r->registered_rules( "Rover::Core" )
  @array = @{$r->registered_rules( )->{"Rover::Core"}}

=item $r->registered_vars( $perlmodname | undef )

Return the list of registered variables for a specific module.

If no module is specified, the return value is a reference to a hash containing
all the variables exported by each module.  The keys of the hash are the module
name, the value is a reference to a list of the registered variables.

=head2 WRITING MODULES

Modules for Rover are simply packages for perl, with a few additional considerations.
Namely, the rules being exported are expected to be called by the rover object
loading the module.  For example: Rover::Core exports the rule "execute", here is
The process for loading and using this rule:

  $r->register_module("Rover::Core");
  $r->execute("host1", "uptime");

When writing the module you need to use Exporter, and export your subroutines.
See the Exporter documentation on how to do this.

One feature of writing Rover modules, is the ability to register and store values
for module variables.  This is usefull if you want your module to be flexible
without having to modify the source code.  To do this, you need to set the variable
@MODULE_NAME::ROVER_VARS.  This example is from the Rover::Core module:

  @Rover::Core::ROVER_VARS = qw(
        $Rover::Core::ftp_append_hostname
        $Rover::Core::command_timeout
        @Rover::Core::FTP::methods
        %Rover::Core::FTP::method_ports
        $Rover::Core::FTP::login_as_self
        $Rover::Core::FTP::login_timeout
  );

These values will then be stored during the next $r->save() call.  However, be
sure you are not storing references to something else.  All values are expected
to be scalar.

The last Rover specific feature is the description.  This is for the benefit
of the user interface.  If you want your module to have a description, set the
$MODULE_NAME::DESCRIPTION value to the text you want.

If one or more of these features are not present, the module will still load
without error.

=head1 NOTES

=item Threading

New to Rover 3.0 is the use of threading.  In v2, threading was only used for
telnet and ftp.  However, we can now use threading for ssh and sftp.  Because
of this all modules are now required to be thread safe.

Rover is considered to be a thread safe module.

=head1 AUTHORS

Current authors:

  Bryan A Bueter

Previous version contributors:

  Erik McLaughlin
  Jayson A Robinson
  John Kellner

=head1 LICENSE

This module can be used under the same terms as Perl.

=head1 DISCLAIMER

THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

