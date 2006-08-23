use 5.006;
use ExtUtils::MakeMaker;
use Config;
use CPAN;

use strict;
use warnings;

# Dependent perl modules needed to run
#
my @dependencies = ("IO::Pty", "IO::Tty", "IO::Stty", "Expect", "IPC::SysV");

my $use_gtk = 1;
my $check_deps = 1;
my $auto_install = 0;

# Have to do this to avoid a later crash if we have to install
# any dependencies
#
my $rover_version = MM->parse_version('lib/Rover.pm');

# determine what to do about dependancies
#
foreach (@ARGV) {
  if (/^--no-gtk$/) {
    $use_gtk = 0;
  }
  if (/^--no-deps$/) {
    $check_deps = 0;
  }
  if (/^--install-deps$/) {
    $auto_install = 1;
  }
}
if ( $use_gtk ) {
  push(@dependencies, "XML::Parser");
  push(@dependencies, "XML::Writer");
  push(@dependencies, "Gtk");
}

my @install_deps = ();
if ( $check_deps ) {
  foreach ( @dependencies ) {
    print "Checking for dependency $_...";
    my $mod = $_;
    $mod =~ s/::/\// ;
    eval { require "$mod.pm" ; };
    if ( $@ ) {
      push(@install_deps, $_ );
      print "no\n";
    } else {
      print "found\n";
    }
  }
}

if ( @install_deps ) {
  if ( $auto_install ) {
    if ( getpwnam($ENV{USER}) ) {
      print "\nYou must be root in order to install dependant modules.\n\n";
      exit(1);
    }
    print "\nMissing modules: @install_deps\n\n";
    foreach my $mod ( @install_deps ) {
      print "Installing $mod via CPAN\n";

      my $obj = CPAN::Shell->expand("Module",$mod);

      if ( $mod eq 'Gtk' ) { CPAN::Shell->o('conf','makepl_arg', '--without-guessing'); }
      eval{ $obj->install; };
      if ( $mod eq 'Gtk' ) { CPAN::Shell->o('conf','makepl_arg', ''); }

      if ( ! $obj->inst_version ) { die "\nDid not install $mod successfully\n\n"; }
    }

    print "
All dependencies have successfully installed , please re-run 'perl Makefile.PL'
in order to continue with the Rover install.

";

  } else {
    print "
Please install the following perl module(s) before continuing:

    @install_deps

You can disable checking for these modules with --no-deps.
You can automatically install them with --install-deps.
";

    if ( $use_gtk ) { print "You can exclude Gtk with --no-gtk\n"; }

    exit(1);
  }
  
} else {
  # See lib/ExtUtils/MakeMaker.pm for details of how to influence
  # the contents of the Makefile that is written.
  if ( $use_gtk ) {
    WriteMakefile(
      NAME              => 'Rover',
      VERSION_FROM      => 'lib/Rover.pm',
      EXE_FILES         => [ qw(scripts/rover scripts/rovergtk) ],
      INSTALLSCRIPT     => '/usr/bin',
      PREREQ_PM         => {
	'IPC::SysV' => 1.03,
        'IO::Tty' => 1.02,
        'IO::Stty' => 0.02,
        'Expect' => 1.15,
        'XML::Parser' => 2.34,
        'XML::Writer' => 0.600,
        'Gtk' => 0.7009,
      },
      ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
        ('ABSTRACT_FROM'  => 'lib/Rover.pm', # retrieve abstract from module
         'AUTHOR'         => 'Bryan Bueter <babueter@sourceforge.net>') : ()),
    );

  } else {
    WriteMakefile(
      NAME              => 'Rover',
      VERSION_FROM      => 'lib/Rover.pm',
      EXE_FILES         => [ qw(scripts/rover) ],
      INSTALLSCRIPT     => '/usr/bin',
      PREREQ_PM         => {
	'IPC::SysV' => 1.03,
        'IO::Tty' => 1.02,
        'IO::Stty' => 0.02,
        'Expect' => 1.15,
      },
      ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
        ('ABSTRACT_FROM'  => 'lib/Rover.pm', # retrieve abstract from module
         'AUTHOR'         => 'Bryan Bueter <babueter@sourceforge.net>') : ()),
    );
  
  }
}

1;
