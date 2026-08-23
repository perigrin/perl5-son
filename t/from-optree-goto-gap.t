# ABOUTME: Tests SoN::FromOptree refuses `goto` loudly instead of dropping it.
# ABOUTME: Both the label form and the `goto &sub` tail-call form share the op name.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;

# `goto` used to VANISH. It is registered in OpMap with an undef node_type and
# no SKIP flag, so the generic branch built nothing and still returned
# 'handled' -- which also made the unknown-op warning unreachable, since that
# only fires for UNREGISTERED ops. Measured before the fix:
#
#   sub { my $x = 1; goto SKIP; $x = 999; SKIP: $x }  ->  Start, Constant, Return
#
# The jump, the statement it skips, and the label all disappeared. Unlike
# `write` (which at least left a visibly odd graph), this one produces a
# constant and a return -- entirely reasonable-looking output that is simply
# missing control flow. That is a miscompile, not a GAP.
#
# NOTHING CURRENTLY COMPILED CONTAINS ONE. Measured: 0 real `goto` statements
# in chalk's lib/ and t/, 0 in perl's t/base (the Phase-5 target) and t/cmd;
# 16 of 227 t/op files, well past the current frontier. This refusal is
# insurance against a silent drop, not a step toward compiling goto.

sub tgt { 7 }

subtest 'the label form is refused' => sub {
    my $err = dies {
        SoN::FromOptree->translate(sub { my $x = 1; goto SKIP; $x = 999; SKIP: $x });
    };

    ok($err, 'translation refuses rather than returning a graph');
    like($err, qr/GAP/, 'refusal is a GAP');
    like($err, qr/\bgoto\b/, 'names the construct the user wrote');
};

subtest 'the goto &sub tail-call form is refused' => sub {
    # Both forms share the op name `goto` (verified with B::Concise: the
    # tail-call compiles to gv / rv2cv / srefgen / goto), so one table entry
    # covers both. Asserted separately because that is a fact about perl's
    # optree, not something the table itself makes obvious.
    #
    # The CV under test must be the one CONTAINING the goto. An earlier probe
    # wrapped it as `sub { goto &tgt }->()` and translated the OUTER sub,
    # which never reaches the goto -- and so reported a false pass.
    my $err = dies { SoN::FromOptree->translate(sub { goto &tgt }) };

    ok($err, 'the tail-call form refuses too');
    like($err, qr/GAP/, 'refusal is a GAP');
};

subtest 'ordinary control flow is untouched' => sub {
    # The refusal is keyed by op NAME, not by the "undef node_type and no SKIP
    # flag" shape -- that shape also covers ops which correctly build nothing
    # because a structural handler owns the construct. A previous attempt to
    # refuse the whole shape broke try/catch, loops and method dispatch.
    ok(lives { SoN::FromOptree->translate(sub { my $t = 0; for my $i (1..3) { $t += $i } $t }) },
        'loops still translate');

    ok(lives { SoN::FromOptree->translate(sub { my $x = 0; try { $x = 1 } catch ($e) { $x = 2 } $x }) },
        'try/catch still translates');

    ok(lives { SoN::FromOptree->translate(sub { my $t = 0; for my $i (1..9) { last if $i > 2; $t += $i } $t }) },
        'loop-control ops (last) still translate');
};

done_testing;
