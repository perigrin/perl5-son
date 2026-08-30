# ABOUTME: `eval BLOCK` must not die with an internal Stack underflow -- it
# ABOUTME: refuses or it lowers, like every other construct.
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

# THE BUG. `eval BLOCK` compiles to entertry/leavetry -- NOT entertrycatch,
# which is perl's `try/catch` feature and the only one the walker handles.
# entertry is registered BRANCH with no handler, so the generic branch-skip
# stepped over it without walking the body, and leavetry then popped a value
# nothing had pushed:
#
#     Stack underflow at lib/SoN/FromOptree/StackSim.pm line 25.
#
# That is an INTERNAL CRASH where a refusal belongs. It violates refuse-or-
# lower in the most damaging way: it fires BEFORE any honest GAP could, so it
# masks whatever the real diagnosis would have been -- and it names StackSim,
# sending a reader after a simulator bug rather than an unhandled construct.
#
# leavetry's own comment records the assumption that was false here: the op
# builds nothing "because a structural handler owns the construct". For
# entertrycatch that is true. For eval BLOCK there is no such handler.
#
# EVERY form was affected, not an edge case: value, void, with and without a
# die in the body.
subtest 'block eval does not crash the translator' => sub {
    for my $src (
        'sub { eval { 1 }; 7 }',
        'sub { my $r = eval { 1 }; $r }',
        'sub { my $r = eval { die "x" }; $r }',
        'sub { eval { print "x" }; 7 }',
    ) {
        my $err = dies { translate($src) };
        unlike($err // '', qr/Stack underflow/,
            "no internal underflow: $src");
        unlike($err // '', qr/StackSim/,
            "no simulator internals leak: $src");
    }
};

# REFUSE OR LOWER. Whichever it does, it must be legible: a GAP naming the
# construct, or a graph. Never an internal error.
subtest 'block eval refuses by name or translates' => sub {
    my $g;
    my $err = dies { $g = translate('sub { my $r = eval { 1 }; $r }') };
    if (defined $err) {
        like($err, qr/GAP/, 'if it refuses, it refuses as a GAP');
        like($err, qr/eval/i, 'and names the construct the user wrote');
    }
    else {
        ok($g, 'or it produces a graph');
    }
};

# THE try/catch PATH IS UNAFFECTED. entertrycatch has a real handler and must
# keep working -- this is the construct block eval was being confused with.
subtest 'try/catch still translates' => sub {
    ok(lives {
        translate('sub { use feature "try"; no warnings; my $x = 0;'
                . ' try { $x = 1 } catch ($e) { $x = 2 } $x }')
    }, 'the try/catch feature is untouched');
};

done_testing;
