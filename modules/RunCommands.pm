#****************************************************************************
# RunCommands for rover
# By: Bryan Bueter, 08/05/2004
#
#****************************************************************************

package RunCommands;
use Exporter;

our $VERSION = "1.00";

my $EOL = "\n";
if ( $os_name == "Rover::Windows" ) {
  $EOL = '';
}

@RunCommands::ISA = qw( Exporter );
@RunCommands::EXPORT = qw( execute send );

$RunCommands::timeout = 15;

sub execute {
  my $command = shift;
  my $exp_obj = shift;

  $exp_obj->clear_accum();
  $exp_obj->send("$command $EOL");
  select(undef,undef,undef,0.25);

  my $result = $exp_obj->expect($RunCommands::timeout,'-re',$Rover::user_prompt);

  if ( ! $result ) {
    print "Error: RunCommands: timed out running command, exiting with failure\n";
    return(0);
  }

  return(1);
}

sub send {
  my $command = shift;
  my $exp_obj = shift;

  $exp_obj->send("$command $EOL");
  select(undef,undef,undef,0.75);
  $exp_obj->clear_accum();

  return(1);
}

1;
