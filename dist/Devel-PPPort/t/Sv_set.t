################################################################################
#
#            !!!!!   Do NOT edit this file directly!   !!!!!
#
#            Edit mktests.PL and/or parts/inc/Sv_set instead.
#
#  This file was automatically generated from the definition files in the
#  parts/inc/ subdirectory by mktests.PL. To learn more about how all this
#  works, please read the F<HACKERS> file that came with this distribution.
#
################################################################################

use FindBin ();

BEGIN {
  if ($ENV{'PERL_CORE'}) {
    chdir 't' if -d 't';
    unshift @INC, '../lib' if -d '../lib' && -d '../ext';
    require Config; import Config;
    use vars '%Config';
    if (" $Config{'extensions'} " !~ m[ Devel/PPPort ]) {
      print "1..0 # Skip -- Perl configured without Devel::PPPort module\n";
      exit 0;
    }
  }

  use lib "$FindBin::Bin";
  use lib "$FindBin::Bin/../parts/inc";

  die qq[Cannot find "$FindBin::Bin/../parts/inc"] unless -d "$FindBin::Bin/../parts/inc";

  sub load {
    require 'testutil.pl';
    require 'inctools';
  }

  if (15) {
    load();
    plan(tests => 15);
  }
}

use Devel::PPPort;
use strict;
BEGIN { $^W = 1; }

package Devel::PPPort;
use vars '@ISA';
require DynaLoader;
@ISA = qw(DynaLoader);
bootstrap Devel::PPPort;

package main;

my $foo = 5;
is(&Devel::PPPort::TestSvUV_set($foo, 12345), 42);
is(&Devel::PPPort::TestSvPVX_const("mhx"), 43);
is(&Devel::PPPort::TestSvPVX_mutable("mhx"), 44);

my $bar = [];

bless $bar, 'foo';
is($bar->x(), 'foobar');

Devel::PPPort::TestSvSTASH_set($bar, 'bar');
is($bar->x(), 'hacker');

if ( "$]" < '5.007003' ) {
    skip 'skip: no SV_NOSTEAL support', 10;
} else {
    ok(Devel::PPPort::Test_sv_setsv_SV_NOSTEAL());

    tie my $scalar, 'TieScalarCounter', 'string';

    is tied($scalar)->{fetch}, 0;
    is tied($scalar)->{store}, 0;
    my $copy = Devel::PPPort::newSVsv_nomg($scalar);
    is tied($scalar)->{fetch}, 0;
    is tied($scalar)->{store}, 0;

    my $fetch = $scalar;
    is tied($scalar)->{fetch}, 1;
    is tied($scalar)->{store}, 0;
    my $copy2 = Devel::PPPort::newSVsv_nomg($scalar);
    is tied($scalar)->{fetch}, 1;
    is tied($scalar)->{store}, 0;
    is $copy2, 'string';
}

package TieScalarCounter;

sub TIESCALAR {
    my ($class, $value) = @_;
    return bless { fetch => 0, store => 0, value => $value }, $class;
}

sub FETCH {
    my ($self) = @_;
    $self->{fetch}++;
    return $self->{value};
}

sub STORE {
    my ($self, $value) = @_;
    $self->{store}++;
    $self->{value} = $value;
}

package foo;

sub x { 'foobar' }

package bar;

sub x { 'hacker' }

