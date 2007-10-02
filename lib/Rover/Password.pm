#****************************************************************************
# Password module for Rover
# By: Bryan Bueter, 09/18/2007
#
#
#****************************************************************************

package Rover::Password;
use Exporter;

BEGIN {
  @Rover::Password::ISA = qw( Exporter );
  @Rover::Password::EXPORT = qw( passwd );

  our $VERSION = "1.00";
}

sub passwd {
  my ($self, $host, $pass) = @_;

  $self->pinfo($host->hostname, "passwd(...)\n");

  if ( ! defined($pass) ) {
    $self->pinfo($host->hostname, "No password supplied\n");
    return(0);
  }

  my $changed_password = 1;
  my $sent_password = 0;
  my $user_password_correct = 0;
  my @user_credentials = $self->user_credentials;

  foreach my $user_password ( @user_credentials ) {
    $host->shell->send("passwd \n");
    select(undef,undef,undef,0.25);

    $host->shell->expect(7,
        [  qr/pick/ , sub { my $fh = shift;
                select(undef,undef,undef,0.25);
                print $fh "p\n";
                select(undef, undef, undef, $0.25);
                exp_continue; } ],
        [ qr/old password:/i , sub { my $fh = shift;
                print $fh "$user_password\n";
                exp_continue; } ],
        [ qr/current.? (unix )?password:/i , sub { my $fh = shift;
                print $fh "$user_password\n";
                exp_continue; } ],
        [ qr/ login password:/ , sub { my $fh = shift;
                print $fh "$user_password\n";
                exp_continue; } ],
        [ qr/assword again:/ , sub { my $fh = shift;
                $user_password_correct = 1;
                print $fh "$pass\n";
                select(undef,undef,undef,0.25);
                $sent_password++;
                exp_continue; } ],
        [ qr/new (unix )?password:/i, sub { my $fh = shift;
                $user_password_correct = 1;
                print $fh "$pass\n";
                select(undef,undef,undef,0.25);
                $sent_password++;
                exp_continue; } ],
        [ qr/sorry/i , sub { $changed_password = 0;
                $self->pinfo($host->hostname, "Error in passwd(), old password incorrect");
                } ],
        [ 'must contain', sub { $changed_password = 0;
                $self->pinfo($host->hostname, "Error in passwd(), new password does not meet requirements");
                } ],
        [ 'Bad password', sub { $changed_password = 0;
                $self->pinfo($host->hostname, "Error in passwd(), new password does not meet requirements");
                } ],
        [ 'unchanged', sub { $changed_password = 0;
                $self->pinfo($host->hostname, "Error in passwd(), new password does not meet requirements");
                } ],
        [ 'do([\s]*n.t) match', sub { $changed_password = 0;
                $self->pinfo($host->hostname, "Error in passwd(), internal error, please report");
                } ],
        [ 'at least', sub { $changed_password = 0;
                $self->pinfo($host->hostname, "Error in passwd(), new password does not meet requirements");
                } ],
        [ 'not contain enough', sub { $changed_password = 0;
                $self->pinfo($host->hostname, "Error in passwd(), new password does not meet requirements");
                } ],
        [ 'too short', sub { $changed_password = 0;
                $self->pinfo($host->hostname, "Error in passwd(), new password does not meet requirements");
                } ],
        [ 'minimum', sub { $changed_password = 0;
                $self->pinfo($host->hostname, "Error in passwd(), new password does not meet requirements");
                } ],
        [ 're-use', sub { $changed_password = 0;
                $self->pinfo($host->hostname, "Error in passwd(), new password does not meet requirements");
                } ],
        [ 'reuse', sub { $changed_password = 0;
                $self->pinfo($host->hostname, "Error in passwd(), new password does not meet requirements");
                } ],
        [ eof => sub { $changed_password = 0; } ],
        [ timeout => sub { $changed_password = 0; } ],
        '-re', $self->user_prompt,
    );
    if ( $user_password_correct ) { last; }
  }

  if ( $changed_password ) {
    return(1);
  } else {
    return(0);
  }

}

1;
