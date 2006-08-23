#****************************************************************************
# Run_Commands for rover
# By: Bryan Bueter, 08/05/2004
#
#****************************************************************************

package Rover::Run_Commands;
use Exporter;

our $VERSION = "1.00";

BEGIN {
  @Rover::Run_Commands::ISA = qw( Exporter );
  @Rover::Run_Commands::EXPORT = qw( execute send );

  $Rover::Run_Commands::timeout = 15;

  Rover::register_module("Rover::Run_Commands", qw( $Rover::Run_Commands::timeout ));
}

sub execute {
  my $command = shift;
  my $exp_obj = shift;
  my $hostname = shift;
  my $os_name = shift;

  my $EOL = "\n";
  if ( $os_name eq "Windows" ) {
    $EOL = '';
  }

  $exp_obj->clear_accum();
  $exp_obj->send("$command $EOL");
  select(undef,undef,undef,0.25);

  my $result = $exp_obj->expect($Rover::Run_Commands::timeout,'-re',$Rover::user_prompt);

  if ( ! $result ) {
    Rover::pinfo($hostname, "Error Run_Commands timed out running command, exiting with failure\n");
    return(0);
  }

  return(1);
}

sub send {
  my $command = shift;
  my $exp_obj = shift;
  my $hostname = shift;
  my $os_name = shift;

  my $EOL = "\n";
  if ( $os_name eq "Windows" ) {
    $EOL = '';
  }

  $exp_obj->send("$command $EOL");
  select(undef,undef,undef,0.75);
  $exp_obj->clear_accum();

  return(1);
}

1;
__END__

=head1 NAME

Rover::Run_Commands - Execute and Send commands for Rover

=head1 SYNOPSYS

  # In config.run file
  #
  GENERAL:{
    ...

    use Rover::Run_Commands;
  };

  Ruleset:{
    execute(uptime);

    send(ps -ef | while read LINE ; do);
    send(  echo $LINE);
    execute(done);
  };

=head1 DESCRIPTION

Run_Commands provides the two most basic commands for Rover, execute
and send.  From the above example you can see how both are used.

=head1 USAGE

=over 4

=item execute()

Execute send a command to the shell and waits for the user prompt to
return.  If a timeout occures before the prompt comes back, it will
fail and return an error.

=item send()

Send simply sends a command to the shell, followed by a carriage return.
It does not wait for the prompt and as long as it is able to write to
the expect object, it will return success.  This can be used for 
multiple line commands, or interacting with a simple program.

=head1 VARIABLES

=item $Rover::Run_Commands::timeout

After sending a command, execute waits this many seconds before giving up
on the return of a prompt.  The default value is 15.

=head1 AUTHORS

Bryan Bueter (babueter@sourceforge.net)

=head1 LICENSE

This module can be used under the same license as Perl.

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
