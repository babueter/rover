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
	_login_methods => [ ("shell_by_ssh", "shell_by_telnet", "shell_by_rlogin") ],
	_login_method_used => undef,
	_ftp => undef,
	_ftp_methods => [ ("sftp", "ftp", "rcp") ],
	_ftp_method_used => undef,
  };

  $self::hostname = shift if @_;

  bless $self, $class;
  return $self;
}

1;

__END__

