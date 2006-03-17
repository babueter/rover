#****************************************************************************
# InteractiveShell for Rover
# By: Bryan Bueter
# Date: 10/10/2004
#
#****************************************************************************

package InteractiveShell;

use Exporter;
@InteractiveShell::ISA = qw( Exporter );
@InteractiveShell::EXPORT = qw( shell );

BEGIN {
  $Rover::paralell_process_count = 1;
}

sub shell {
  my $command = shift;
  my $exp_obj = shift;
  my $hostname = shift;
  my $os = shift;

  $exp_obj->send("#~Interactive Shell Start\n");
  my $got_prompt = 1;
  $exp_obj->expect(5,
	[ 'timeout' => sub {
		print "$hostname:\trunme: could not get prompt, system may be running slow.\n" if $Rover::debug > 1;
		$got_prompt = 0;
		}],
	'-re', $Rover::user_prompt, );

  if ( ! $got_prompt ) {
    return 0;
  }

  print "###########################################\n";
  print "### Interactive shell on '$hostname'\t###\n";
  print "### Return to rover run with CTRL+D\t###\n";
  print "###########################################\n\n";
  print $exp_obj->before() . $exp_obj->match();

  #$exp_obj->slave->clone_winsize_from(\*STDIN);
  $exp_obj->interact(\*STDIN,"\cD");
  print "\n\n\n";

  return 1;
}

1;
