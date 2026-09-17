# ABOUTME: A block eval's result Phi is stamped from the join of its two arms.
# ABOUTME: Unstamped, it cannot serve as a loop-carried back-edge and the loop is refused.

use v5.42.0;
use Test2::V0;
use JSON::PP;

sub translate ($src) {
    my $file = __FILE__ . ".tmp.$$.pl";
    open my $fh, '>', $file or die $!;
    print $fh $src;
    close $fh;
    my $err = qx($^X -Ilib -MO=SoN,json,package=main $file 2>&1 >/dev/null);
    my $out = qx($^X -Ilib -MO=SoN,json,package=main $file 2>/dev/null);
    unlink $file;
    my $data = eval { JSON::PP->new->decode($out) };
    return ($data ? $data->{methods}{'main::__PROGRAM__'} : undef, $err);
}

# An eval's value is `Phi(body_value, Undef)` -- the body's result, or undef if
# it died. That Phi was built with NO stamp, so it defaulted to Unknown, the
# lattice TOP.
#
# Outside a loop nothing noticed. Inside one it is fatal: an accumulator fed by
# an eval makes the eval's Phi the loop Phi's BACK-EDGE, and _patch_loop_phi
# refuses an unstamped back-edge -- correctly, because unstamping the loop Phi
# would leave the already-stamped body contaminating sibling joins.
#
# The join is available right where the Phi is built, and every other merge-Phi
# site in the walker already stamps from it for exactly this reason (see the
# and/or merge sites: "a merge Phi over a loop-carried accumulator becomes that
# slot's back-edge, and _patch_loop_phi rejects an UNSTAMPED back-edge").
subtest 'an eval Phi is stamped from its arms' => sub {
    my ($g, $err) = translate('my $r = eval { 42 }; print "$r\n";');
    ok defined $g, 'it translates' or diag($err), return;

    my ($phi) = grep { $_->{op} eq 'Phi' } $g->{nodes}->@*;
    ok defined $phi, 'the eval built a Phi' or return;

    # join(Int, Undef) is Scalar: the value is an Int when the body returned
    # and undef when it died, and Scalar is the narrowest thing that covers
    # both. NOT Unknown, which is the top and asserts nothing.
    is $phi->{stamp}, 'Scalar',
        'the Phi carries the join of its arms, not the lattice top';
};

# THE LOOP CASE IS THE ONE THAT WAS REFUSED. The eval Phi becomes the back-edge
# of the accumulator's loop Phi, and an unstamped back-edge means the init
# stamp cannot be trusted past the first iteration.
subtest 'an accumulator fed by an eval lowers' => sub {
    my ($g, $err) = translate(<<'SRC');
my $t = 0;
for my $i (1,2) { my $r = eval { $i }; $t += $r }
print "$t\n";
SRC
    unlike $err, qr/GAP:/, 'it is not refused' or diag $err;
    ok defined $g, 'it translates' or return;

    my @ops = map { $_->{op} } $g->{nodes}->@*;
    ok scalar(grep { $_ eq 'Loop' } @ops), 'the loop is in the graph';

    # No Phi in the graph may be left at the lattice top: that is the state
    # the refusal existed to prevent reaching the wire.
    my @unstamped = grep { $_->{op} eq 'Phi' && ($_->{stamp} // '') eq 'Unknown' }
                    $g->{nodes}->@*;
    is scalar(@unstamped), 0, 'no Phi reaches the wire unstamped'
        or diag join ' ', map { "$_->{id}:$_->{stamp}" } @unstamped;
};

# THE WIDENING GUARD WAS OVER-BROAD, and it is not an eval question at all:
# these are ordinary accumulators. `my $t = 0; $t += 0.5` starts the Phi at Int
# from its init and the back-edge arrives Num, so the join widens and the guard
# fired.
#
# It exists for a real defect -- the body was walked under the optimistic init
# stamp, so widening the Phi alone can leave a stale narrower stamp behind --
# but that is a property to MEASURE, not to assume. Measured on the Phi's
# consumer cone:
#
#     $t += 0.5              cone Phi/Int Coerce/Num Add/Num   -- nothing stale
#     $s = $s . "x"          cone Phi/Int Coerce/Str ...       -- nothing stale
#     my $u=$t+1; $t+=0.5    cone contains Add/Int             -- STALE
#
# The Coerce the walker inserts at the use site does the widening already; only
# a consumer that read the Phi directly at the narrower type is stale.
subtest 'an ordinary widening accumulator lowers' => sub {
    for my $case (
        ['num', 'my $t=0; for my $i (1,2) { $t += 0.5 } print "$t\n";'],
        ['str', 'my $s=0; for my $i (1,2) { $s = $s . "x" } print "$s\n";'],
    ) {
        my ($name, $src) = $case->@*;
        my ($g, $err) = translate($src);
        unlike $err, qr/GAP:/, "$name: not refused" or diag $err;
    }
};

# THE "STALE" CASE IS NOT STALE -- IT IS RESTAMPED. This subtest used to assert
# that `my $u = $t + 1; $t += 0.5` stays refused, on the reading that a consumer
# which read the Phi before the back-edge widened it holds a claim that is now
# wrong.
#
# The claim is wrong; the RESPONSE was. A widened Phi does not invalidate its
# cone, it re-types it: Add(Phi/Int, Int) simply becomes Add(Phi/Num, Int), and
# TypeLibrary already says what that yields. Measured, the graph this produces
# is correct --
#
#     Phi in=[Constant/Int, Add/Num] stamp=Num     the accumulator, widened
#     Phi in=[Constant/Int, Add/Int] stamp=Int     the counter, UNCHANGED
#     Add in=[Phi/Num, Constant/Int] stamp=Num     the once-"stale" consumer
#
# -- and it round-trips: perl prints `u=1 u=1.5 t=1` and so does the emitted
# program.
#
# The old predicate could not see this because it compared a consumer's RESULT
# against its OPERAND's join. A comparison is where that shows: NumLt yields
# Boolean for any operands, yet join(Boolean, Num) is Scalar, so every
# comparison reading a widened Phi was flagged. Measured across the suite, ALL
# 43 flagged nodes were comparisons -- NumLt 16, NumGt 14, NumEq 7, NumNe 5,
# NumGe 1 -- and not one can be stale by construction.
subtest 'a widening consumer is restamped, not refused' => sub {
    my ($g, $err) = translate(
        'my $t=0; for my $i (1,2) { my $u = $t + 1; $t += 0.5 } print "$t\n";');
    unlike $err, qr/GAP:/, 'it translates' or diag $err;
    ok $g, 'and produces a graph' or return;

    # translate() returns the __PROGRAM__ METHOD, not the whole wire.
    my @nodes = (($g->{nodes}) // [])->@*;
    my %by = map { $_->{id} => $_ } @nodes;
    my @phi = grep { ($_->{op} // '') eq 'Phi' } @nodes;

    ok( ( grep { ($_->{stamp} // '') eq 'Num' } @phi ),
        'the accumulator Phi widened to Num' );
    ok( ( grep { ($_->{stamp} // '') eq 'Int' } @phi ),
        'while the counter Phi is still Int' );

    # No consumer may be left claiming a type NARROWER than what its inputs
    # now yield -- that is the miscompile the old refusal was guarding, and
    # restamping is what actually prevents it.
    my @narrow = grep {
        my $n = $_;
        ($n->{op} // '') eq 'Add'
            && ($n->{stamp} // '') eq 'Int'
            && grep { (($by{$_}{stamp}) // '') eq 'Num' } (($n->{inputs}) // [])->@*
    } @nodes;
    is scalar(@narrow), 0, 'no Add is left stamped Int over a Num operand';
};

done_testing;
