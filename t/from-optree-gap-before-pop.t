# ABOUTME: A refused op must GAP before it pops -- popping first underflows the
# ABOUTME: stack and reports a simulator error instead of naming the construct.
use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

sub translate ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

# THE ORDERING BUG. The generic op handler read pop_count from the OpMap and
# popped that many operands BEFORE checking whether the op is a declared GAP.
# A refused op still carries a pop_count, so it popped operands it does not
# have:
#
#     goto:  pop_count=1  node_type=undef
#
# and `goto FOO; print "x"` died with "Stack underflow at StackSim.pm line 25"
# -- an internal error raised a few lines above the GAP that would have named
# `goto`. The reader is sent after a simulator bug instead of an unlowered
# construct.
#
# This is the same masking shape that hid block eval: the crash fires BEFORE
# the honest refusal, so the refusal never runs and the real diagnosis is lost.
subtest 'a refused op names itself rather than underflowing' => sub {
    for my $src (
        'sub { goto FOO; print "x" }',
        'sub { my $x = 1; goto SKIP; $x = 999; SKIP: $x }',
        'sub { if ($^O eq "os2") { goto FOO } else { print "b" } FOO: print "x" }',
    ) {
        my $err = dies { translate($src) };
        ok($err, "refuses: $src") or next;
        unlike($err, qr/Stack underflow/, "no underflow: $src");
        unlike($err, qr/StackSim/,        "no simulator internals: $src");
        like($err,   qr/GAP/,             "is a GAP: $src");
        like($err,   qr/goto/,            "names the construct: $src");
    }
};

# THE FIX MUST NOT SWALLOW WORKING OPS. The GAP check runs before the pop, so
# an op that is NOT in the table must still pop and build normally.
subtest 'ops that are not refused still translate' => sub {
    ok(lives { translate('sub { my $x = 1; $x + 1 }') },
        'arithmetic still builds');
    ok(lives { translate('sub { print "x"; 7 }') },
        'a mark-popping op still builds');
    ok(lives { translate('sub { eval { 1 }; 7 }') },
        'block eval still builds');
};

done_testing;
