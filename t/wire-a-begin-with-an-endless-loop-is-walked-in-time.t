# ABOUTME: A BEGIN block holding a loop with no condition (while (1), for (;;))
# ABOUTME: is walked for its requires in time: the op_next walk stops at a cycle.

use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);
use B ();

my $dir = tempdir(CLEANUP => 1);

# The producer runs under timeout(1): a hang kills the child and FAILS the
# case (exit 124) instead of wedging the suite.
sub producer ($src) {
    my $f = "$dir/g." . int(rand 1e9) . ".pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $j = qx(/usr/bin/timeout 300 $^X -Ilib -MO=-q,SoN,json $f 2>$dir/err);
    my $exit = $? >> 8;
    unlink $f;
    return ( $exit, eval { JSON::PP->new->decode($j) } );
}

sub wire_in_time ($src, $name) {
    my ( $exit, $w ) = producer($src);
    isnt $exit, 124, "$name: the producer finishes within 300 seconds";
    is $exit, 0, "$name: the producer exits 0";
    ok $w && $w->{methods}{'main::__PROGRAM__'}, "$name: a wire with the program";
}

# _required_files FOLLOWED op_next WITH NO VISITED SET. A loop with no
# condition has no exit on that chain -- `last` leaves by the loop's lastop --
# so the walk went round forever (docs/memory/a-timeout-can-be-a-hang.md).
wire_in_time(<<'SRC', 'while (1) in a BEGIN');
BEGIN { my $i = 0; while (1) { last if $i++ > 2 } }
print "ok\n";
SRC

wire_in_time(<<'SRC', 'a C-style for with no condition in a BEGIN');
BEGIN { for (my $j = 0; ; $j++) { last if $j > 2 } }
print "ok\n";
SRC

# Math::BigInt::Calc has such a loop in a BEGIN of its own, and a followed
# module's BEGIN blocks are walked too.
wire_in_time(<<'SRC', 'use Math::BigInt');
use Math::BigInt;
print "ok\n";
SRC

# WHAT THE WALK RETURNS IS UNCHANGED where it already ended: the requires
# on the op_next chain, in order.
require B::SoN;
my $cv = B::svref_2object( sub { require Carp; require File::Spec; my $x = 1 } );
is [ B::SoN::_required_files($cv) ], [ 'Carp.pm', 'File/Spec.pm' ],
    'the requires of a constant on the chain, in order';

my @files = eval {
    local $SIG{ALRM} = sub { die "timeout\n" };
    alarm 30;
    my @f = B::SoN::_required_files(
        B::svref_2object( sub { require Carp; my $i = 0; while (1) { last if $i++ > 2 } } ) );
    alarm 0;
    @f;
};
alarm 0;
is $@, '', 'a sub with an endless loop is walked within 30 seconds';
is \@files, ['Carp.pm'], '... and the require before the loop is found';

done_testing;
