# ABOUTME: `while (1) { ... last if C }` is a loop whose ONLY exit is the break.
# ABOUTME: perl folds the constant condition away; the break is still lowerable.
use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub ops_of ($g, $op) { return grep { $_->operation eq $op } $g->nodes->@* }

# THE GAP. `while (1)` is not a loop with a trivial condition -- perl folds the
# constant away entirely, so `enterloop` has NO condition op at all and the only
# exit is the `last`:
#
#     6  <{> enterloop(next->h last->i redo->7) v
#     ...
#     f  <|> and(other->g) vK/1        <- `last if $x == 3`
#     g      <0> last v*
#
# The walker required a HEADER exit edge ($exit_proj) and GAPped without one,
# even though `@break_projs` already collects exactly this shape and Phase 5
# already builds the exit Region from `($exit_proj, @break_projs)`. The machinery
# was complete; only the assumption that a header exit must exist was wrong.
#
# THIS IS A COMMON IDIOM, not an exotic case: `while (1) { ... last if ... }` is
# how a mid-test loop is spelled in perl, and it is what perl's own
# t/base/while.t tests second. That whole file compiled to `{}` -- an empty
# methods object, a worse wire than any Unknown stamp.
subtest 'while (1) with a mid-body last is lowered' => sub {
    my $g = graph_of('sub { my $x = 0; while (1) { $x = $x + 1; last if $x == 3; } $x }');
    ok($g, 'the graph exists') or return;
    ok(scalar(ops_of($g, 'Loop')), 'a Loop node is built');
    ok(scalar(ops_of($g, 'Add')),  'the body is translated');
};

# THE EXIT IS THE BREAK. With no header test there is exactly ONE exit
# predecessor, and it is the break's Proj -- not a header-false edge.
subtest 'the exit Region is reached from the break' => sub {
    my $g = graph_of('sub { my $x = 0; while (1) { $x = $x + 1; last if $x == 3; } $x }');
    my ($loop) = ops_of($g, 'Loop');
    ok($loop, 'the Loop node exists') or return;
    my $exit = $loop->region;
    ok($exit, 'the Loop has an exit Region') or return;
    is($exit->operation, 'Region', 'the exit is a Region');
    ok(scalar($exit->inputs->@*) >= 1, 'it has at least one predecessor');
};

# A CONDITIONED LOOP IS UNAFFECTED -- the header exit still drives it, and this
# is the case that worked before. Without this the change could not be told
# apart from removing the exit requirement altogether.
subtest 'a normal while loop still lowers through its header' => sub {
    my $g = graph_of('sub { my $x = 0; while ($x != 3) { $x = $x + 1; } $x }');
    ok(scalar(ops_of($g, 'Loop')), 'a Loop node is built');
    ok(scalar(ops_of($g, 'Phi')),  'and it carries a loop Phi');
};

# AND A LOOP WITH NEITHER A CONDITION NOR A BREAK MUST STILL GAP. `while (1) {}`
# with no exit is an infinite loop; refusing it is correct, and a change that
# merely deleted the check would wrongly accept it.
subtest 'a loop with no exit at all still GAPs' => sub {
    my $err = dies {
        graph_of('sub { my $x = 0; while (1) { $x = $x + 1; } $x }')
    };
    ok($err, 'it refuses') or return;
    like($err, qr/GAP/, 'and it is a GAP, not a crash');
};

# AN UNCONDITIONAL `next` ENDS THE BODY, and everything after it is dead. perl
# agrees -- `while ($x != 3) { $x = $x + 1; next; print "not "; }` prints no
# "not " at all, because `next` at op c jumps to the loop's continue point (h,
# `unstack`) and ops d..g are unreachable:
#
#     c      <0> next v*
#     d      <;> nextstate ...        <- from here down, dead
#     g      <@> print vK
#     h      <0> unstack v            <- where `next` goes
#
# The walker already treats `unstack` as "stop walking the body". An
# unconditional `next` is the same instruction one op earlier, so it stops the
# body walk the same way rather than GAPping. This is perl's t/base/while.t
# test 3, and it is the second of the two GAPs that made that whole file
# compile to an empty methods object.
#
# `last` IS NOT THE SAME and is deliberately left refused: it leaves the loop
# rather than continuing it, so the exit Region needs its edge and its bindings.
# A `next` rejoins the header, which the back-edge already carries.
subtest 'an unconditional next ends the body, and the dead tail is dropped' => sub {
    my $g = graph_of('sub { my $x = 0; while ($x != 3) { $x = $x + 1; next; my $d = 99; } $x }');
    ok($g, 'the graph exists') or return;
    ok(scalar(ops_of($g, 'Loop')), 'a Loop node is built');
    ok(scalar(ops_of($g, 'Add')),  'the live part of the body is translated');

    # THE TEETH: the dead tail must NOT be in the graph. Without this the
    # subtest would pass on a walker that simply ignored `next` and kept going.
    my @dead = grep { ($_->can('value') ? ($_->value // '') : '') eq '99' }
               $g->nodes->@*;
    is(scalar @dead, 0, 'the statement after `next` is not translated');
};


# THE HEADER CONDITION IS ATTACHED, NOT BRANCHED -- the mirror of the gap above,
# and the thing that makes a Loop readable without a heuristic.
#
#     while ($x != 3) { $x = $x + 1; }
#
# builds a Loop, a Phi, an Add and a NumNe -- and NO If. Reading the graph by
# `inputs` alone, that NumNe looks DEAD: nothing consumes it. It is not. It
# carries a CONTROL edge to the Loop (`control_in`), which is how the consumer
# recovers which comparison is the loop's continuation test. FromOptree's own
# comment at that site records why: recovering it structurally beats the
# ambiguous "first icmp consuming a header Phi" heuristic, "which a body
# comparison can hijack".
#
# The two forms are deliberately asymmetric, and both halves are asserted here:
#
#   header `while (C)`   -- C attaches to the Loop by control_in; Projs hang off
#                           the Loop itself. No If.
#   mid-body `last if C` -- C is consumed by a real If; a break is a genuine
#                           control split, so it branches.
#
# Asserted because a reader auditing this graph for liveness WILL read the NumNe
# as an unwired dead node and "fix" it into an infinite loop that now branches.
subtest 'a written header condition attaches to the Loop' => sub {
    my $g = graph_of('sub { my $x = 0; while ($x != 3) { $x = $x + 1; } $x }');
    ok($g, 'the graph exists') or return;

    my ($loop) = ops_of($g, 'Loop');
    my ($cmp)  = ops_of($g, 'NumNe');
    ok($loop && $cmp, 'the Loop and its condition both exist') or return;

    ok($cmp->control_in, 'the condition carries a control edge') or return;
    is($cmp->control_in->id, $loop->id,
        'the header condition attaches to the Loop -- not dead, just not an If');

    is(scalar(ops_of($g, 'If')), 0,
        'a header-only loop builds no If: the Loop IS the test');
};

# THE OTHER HALF. A mid-body break is a real control split, so its condition is
# consumed by an If and does NOT attach to the Loop. If both forms ever collapse
# to the same shape, one of them is wrong.
subtest 'a mid-body break condition branches instead' => sub {
    my $g = graph_of('sub { my $x = 0; while (1) { $x = $x + 1; last if $x == 3; } $x }');
    my ($cmp) = ops_of($g, 'NumEq');
    ok($cmp, 'the break condition exists') or return;

    my @ifs = ops_of($g, 'If');
    my $consumed = grep {
        grep { defined && $_->id eq $cmp->id } $_->inputs->@*
    } @ifs;
    ok($consumed, 'a break condition IS consumed by an If');
};

done_testing;
