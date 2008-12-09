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
	_description => "",
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

sub description {
  my ($self, $description) = @_;

  $self->{_description} = $description if $description;
  return $self->{_description};
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

=head1 NAME

Rover::Ruleset - Ruleset object for the Rover module

=head1 SYNOPSIS

  # Start with the Rover object
  use Rover;
  my $r = new Rover;

  # Store the object inside Rover
  my $ruleset_obj = $r->add_ruleset("Ruleset 1");

  # Set/Get the text description of the ruleset
  my $desc = $ruleset_obj->description();
    or
  $ruleset_obj->description("Text Description");

  # Set or return the list of OS's this ruleset can
  # run on.
  $ruleset_obj->os_list()
    or
  $ruleset_obj->os_list(@OS_LIST);

  # Add a rule to the ruleset
  $ruleset_obj->add("execute", "uptime");

  # Delete a rule by index
  $ruleset_obj->delete($integer);

  # Clear all rules
  $ruleset_obj->clear();

  # Return a formatted list of rulesets
  $ruleset_obj->list();

  # Return an array of references to the rules themselves
  my @commands = $rulest_obj->commands();
  $rule1_comm = $commands[0]->[0];
  $rule1_args = $commands[0]->[1];


=head1 DESCRIPTION

Rover::Ruleset is the object class for storing ruleset objects inside Rover.

=head1 AUTHORS

  Bryan A Bueter

=head1 LICENSE

This module can be used under the same terms as Perl.

=head1 DISCLAIMER

THIS SOFTWARE IS PROVIDED ‘‘AS IS’’ AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE
AUTHORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
SUCH DAMAGE.

