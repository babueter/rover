# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Rover.t'

#########################

use strict;
use Test;
BEGIN { plan tests => 32 };

# Test loading the Rover module and doing some
# object manipulation
#
require Rover;
ok(1);

my $r = Rover->new();
if ( $r ) {
  ok(1);
} else {
  ok(0);
}

$r->register_module("Rover::Core");
ok(1);

$r->add_hosts("127.0.0.1", "localhost");
my $host = $r->host("127.0.0.1");
if ( $host ) {
  ok(1);
} else {
  ok(0);
}

$r->add_rulesets("test");
my $ruleset = $r->ruleset("test");
if ( $ruleset ) {
  ok(1);
} else {
  ok(0);
}

$ruleset->add("execute", "uptime");
ok(1);

# Make sure Expect and threads modules load
#
require Expect;
ok(1);

require threads;
require threads::shared;
ok(1);

# Try to expect while threading.  Do it several times
#
sub run_threaded {
  my $exp = shift;
  my $h = shift;

  $exp->expect(5, 'eof');
  $$h = $exp->before();
  chomp $$h;
  chop $$h;
}

my $hostname = `hostname`;
chomp $hostname;

for (my $i=0; $i<4; $i++) {
  my $exp1 = new Expect;
  my $exp2 = new Expect;
  ok(1);

  $exp1->spawn("hostname");
  $exp2->spawn("hostname");
  ok(1);

  my $h1 : shared;
  my $h2 : shared;

  my $t1 = threads->new("run_threaded", $exp1, \$h1);
  my $t2 = threads->new("run_threaded", $exp2, \$h2);
  ok(1);

  $t1->join();
  $t2->join();
  ok(1);

  if ( $h1 eq $hostname ) { ok(1); } else { ok(0); }
  if ( $h2 eq $hostname ) { ok(1); } else { ok(0); }
}

