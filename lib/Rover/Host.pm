#****************************************************************************
# Host module for Rover
# By: Bryan Bueter, 03/23/2007
#
#
#****************************************************************************

package Rover::Host;
use Exporter;

BEGIN {
  our $VERSION = "1.00";
}

sub hostname {
  my ($self, $hostname) = @_;

  $self->{_hostname} = $hostname if defined($hostname);
  return $self->{_hostname};
}

sub os {
  my ($self, $os) = @_;

  $self->{_os} = $os if defined($os);
  return $self->{_os};
}

sub username {
  my ($self, $username) = @_;

  $self->{_username} = $username if defined($username);
  return $self->{_username};
}

sub passwords {
  my $self = shift;
  my @passwords = @_;

  $self->{_passwords} = \@passwords if @passwords;
  return @{$self->{_passwords}};
}

sub description {
  my ($self, $description) = @_;

  $self->{_description} = $description if defined($description);
  return($self->{_description});
}

sub shell {
  my ($self, $shell) = @_;

  $self->{_shell} = $shell if defined($shell);
  return($self->{_shell});
}

sub login_methods {
  my $self = shift;
  my @login_methods = @_;

  $self->{_login_methods} = \@login_methods if @login_methods;
  return @{$self->{_login_methods}};
}

sub login_method_used {
  my ($self, $method) = @_;

  $self->{_login_method_used} = $method if defined($method);
  return $self->{_login_method_used};
}

sub ftp {
  my ($self, $ftp) = @_;

  $self->{_ftp} = $ftp if defined($ftp);
  return($self->{_ftp});
}

sub ftp_methods {
  my $self = shift;
  my @ftp_methods = @_;

  $self->{_ftp_methods} = \@ftp_methods if @ftp_methods;
  return @{$self->{_ftp_methods}};
}

sub ftp_method_used {
  my ($self, $method) = @_;

  $self->{_ftp_method_used} = $method if defined($method);
  return $self->{_ftp_method_used};
}

sub soft_close {
  my $self = shift;

  if ( $self->shell ) {
    $self->shell->send("exit;\n exit;\n exit;\n");
    $self->shell->send(EOF);
    $self->shell->send(EOF);
    $self->shell->send(EOF);
    select(undef, undef, undef, 0.25);
    $self->shell->soft_close();

    $self->shell(0);
  }
  if ( $self->ftp ) {
    if ( $self->ftp_method_used ne "ftp" ) {
      $self->ftp->send("quit\n");
      select(undef, undef, undef, 0.25);
      $self->ftp->soft_close();
    }
    $self->ftp(0);
  }
  return undef;
}

sub hard_close {
  my $self = shift;

  if ( $self->shell ) {
    $self->shell->hard_close();
    $self->shell(0);
  }
  if ( $self->ftp ) {
    if ( $self->ftp_method_used ne "ftp" ) {
      $self->ftp->hard_close();
    }
    $self->ftp(0);
  }
  return undef;
}

sub new {
  my $class = shift;
  my $self = {
	_hostname => shift,
	_os => shift,
	_username => shift,
	_passwords => [ @_ ],
	_description => undef,
	_shell => 0,
	_login_methods => [( )],
	_login_method_used => undef,
	_ftp => undef,
	_ftp_methods => [( )],
	_ftp_method_used => undef,
  };

  $self::hostname = shift if @_;

  bless $self, $class;
  return $self;
}

1;

__END__

=head1 NAME

Rover::Host - Host object for the Rover module

=head1 SYNOPSIS

  # Start with the Rover object
  use Rover;
  my $r = new Rover;

  # Store the object inside Rover
  my $host_obj = $r->add_host("host1");

  # Return the hostname of the current host object
  my $host = $host_obj->hostname();

  # Return or set the OS type
  my $os = $host_obj->os();
    or
  $host_obj->os("OS");

  # Set the username to log into for this host only.
  # Default is to use $r->user();
  #
  $host_obj->username("username");

  # Set the list of passwords to use on this host only.
  # Default is to use $r->user_credentials
  #
  $host_obj->passwords(@password_list);

  # Set the text description for this host.
  $host_obj->description("Text Description");

  # Return the Expect objects for shell and ftp sessions
  $host_obj->shell();
  $host_obj->ftp();

  # Close the Expect objects for this host.  See Expect documentation
  # for the differences between soft_close and hard_close
  #
  $host_obj->soft_close();
  $host_obj->hard_close();

=head1 DESCRIPTION

Rover::Host is the object class for storing host objects inside Rover.

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

