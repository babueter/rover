#****************************************************************************
# Ruleset module for Rover
# By: Bryan Bueter, 03/23/2007
#
#
#****************************************************************************

package Rover::Ruleset;
use Exporter;

BEGIN {
  our $VERSION = "1.00";
}

sub new {
  my $class = shift;
  
  my @commands = ();
  my @os_list = ();
  my $self = {
	_commands => \@commands,
	_os_list => \@os_list,
  };

  bless $self, $class;
  return $self;
}

sub os_list {
  my $self = shift;
  my @os_list = @_;

  $self->{_os_list} = \@os_list if @os_list;
  return @{$self->{_os_list}} ;
}

sub add {
  my ($self, $command, $args) = @_;

  return (0) if ! $command;

  my @ruleset_command = ($command, $args);
  push( @{$self->{_commands}}, \@ruleset_command);

  return (1);
}

sub delete {
  my ($self, $line) = @_;

  if ( defined($self->{_commands}->[$line]) ) {
    my $count = @{$self->{_commands}} ;
    my @new_ruleset = ();
    for (my $i=0; $i<$count; $i++) {
      next if $i == $line-1;

      push( @new_ruleset, $self->{_commands}->[$i] );
    }

    $self->{_commands} = \@new_ruleset;
    return(1);

  } else {
    return(0);
  }
}

sub clear {
  my $self = shift;

  my @new_ruleset = ();
  $self->{_commands} = \@new_ruleset;

  return(1);
}

sub commands {
  my $self = shift;

  return( @{$self->{_commands}} );
}

sub list {
  my $self = shift;

  my @ruleset = ();
  foreach my $command ( @{$self->{_commands}} ) {
    my $ruleset_command = $command->[0] ."(". $command->[1] .");" ;
    push (@ruleset, $ruleset_command);
  }

  return(@ruleset);
}


1;

__END__

