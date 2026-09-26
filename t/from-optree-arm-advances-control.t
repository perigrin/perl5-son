#!/usr/bin/env perl
# ABOUTME: An and/or arm that ADVANCES CONTROL -- a call whose result is read, a loop --
# ABOUTME: must build the If, and an arm that RETURNED must not also be a merge input.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# ---------------------------------------------------------------------------
# WHY THIS EXISTS
#
# perl folds a one-armed `if` into `and`, so the and/or handler is where a
# one-armed branch is built. Its gate asked "does this arm hold an EFFECT"
# (_arm_has_element_store / _arm_has_field_store / _arm_has_void_call /
# _arm_has_die). That is not the same question as "does this arm ADVANCE
# CONTROL", and two shapes answer the first `no` while still advancing:
#
#   1. A CALL WHOSE RESULT IS READ. _handle_entersub pins control_in on EVERY
#      Call (R1.0 effect-by-default), but _arm_has_void_call tests
#      OPf_WANT_VOID -- so a call that is the construct's VALUE reported no
#      effect, no If was built, and the Call was left pinned UNCONDITIONALLY.
#
#   2. A LOOP IN THE ARM. map/grep/foreach/while each build a Loop whose exit
#      Region becomes the new control -- but on the arm's DISCARDED snapshot.
#      Without an If, that exit control is thrown away and the Loop is left a
#      control sibling of whatever the base built.
#
# Separately, an arm that RETURNS does not rejoin: its control edge already
# went to the function-exit accumulator, and Regioning it at the branch too put
# one control node in two merges.
#
# Each defect shows up as a node with TWO control successors, which is what the
# deparse oracle refuses to render -- honestly, because the graph is wrong.
# ---------------------------------------------------------------------------

sub translate ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $cerr = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $cerr" if $cerr;
    return SoN::FromOptree->translate($cv);
}

# Every node that names $node on control_in, plus every Region that takes it as
# an input (a Region consumes its predecessors as data inputs, not control_in).
# This is the count the deparse oracle's refusal is keyed on.
sub control_successors ($g, $node) {
    my @out;
    for my $n ($g->nodes->@*) {
        push @out, $n
            if defined $n->control_in && $n->control_in->id eq $node->id;
        next unless $n->operation eq 'Region';
        push @out, $n
            if grep { defined $_ && ref $_ && $_->id eq $node->id }
                    $n->inputs->@*;
    }
    my %seen;
    return grep { !$seen{ $_->id }++ } @out;
}

sub nodes_of ($g, $op) {
    return grep { $_->operation eq $op } $g->nodes->@*;
}

# Every node that forks control without being an If or a Loop -- the exact
# shape the deparse oracle refuses ("a control node with N successors is not
# yet rendered"). Reported as a list of readable descriptions so a failure
# names the fork rather than the whole graph.
sub forks ($g) {
    my @bad;
    for my $n ($g->nodes->@*) {
        next if $n->operation eq 'If' || $n->operation eq 'Loop';
        my @succ = control_successors($g, $n);
        next if @succ <= 1;
        push @bad, sprintf('%s -> [%s]', $n->operation,
                           join(' ', map { $_->operation } @succ));
    }
    return @bad;
}

# KIND A -- a short-circuited call is pinned unconditionally.
#
#     sub c { 7 }
#     sub foo { my $s = shift; if ($s) { main::c() } }
#
# perl folds this to `shift and main::c()`, and main::c() is the sub's return
# value -- NOT void. Measured before the fix:
#
#     3 Call(shift)  ci=0      4 Call(main::c) ci=3
#     5 And(3,4)               6 Return in=[5]  ci=3
#
# Call(3) has two control successors (4 and 6), which is not two control paths:
# Return(6) reads And(5) reads Call(4), so 6 must FOLLOW 4. It is one linear
# chain mis-stamped -- and the call perl short-circuits away sits on it
# unconditionally. Measured with a printing c() and foo(0): perl prints
# nothing; the graph runs the call.
subtest 'a non-void call in an and-arm is guarded, not pinned unconditionally' => sub {
    my $g = translate('sub main::c { 7 } sub { my $s = shift; if ($s) { main::c() } }');

    my ($call) = grep { ($_->name // '') eq 'main::c' } nodes_of($g, 'Call');
    ok $call, 'the main::c() Call is in the graph' or return;

    my ($if) = nodes_of($g, 'If');
    ok $if, 'an If was built for the folded one-armed if' or return;

    my $ctrl = $call->control_in;
    ok defined $ctrl, 'the Call is control-pinned' or return;
    is $ctrl->operation, 'Proj',
        'and it is pinned on a Proj -- the guarded arm, not the base chain';
    is $ctrl->inputs->[0]->id, $if->id, 'that Proj belongs to the If';

    # THE SHAPE THE ORACLE REFUSES. Nothing on the chain may fork without an
    # If/Loop saying so.
    is [forks($g)], [], 'no node but an If/Loop has two control successors';
};

# KIND C -- a loop in the RHS of and/or is built in a discarded snapshot.
#
#     my @f = (1,2);
#     if (!$ENV{NO_SLEEP} and grep -e, @f) { print "s\n" }
#
# The grep is the RHS of the outer `and`, and it holds no effect at all -- so
# the effect gate said no, no If was built, and _translate_foreach_array's
# `$sim->set_control($exit_region)` landed on the DISCARDED snapshot. Measured:
#
#     Loop 6 in=[0] ci=0        If 10 in=[0,9] ci=0
#
# two control nodes on Start. THE DECISIVE CONTROL: the same program with the
# grep as the LHS is correct, and so is `if (grep ...)` with no `and` -- only
# the RHS position broke, which is what says the snapshot is where it is lost.
#
# The RHS of `and` is SHORT-CIRCUITED, so its control is conditional: hoisting
# the loop onto the base chain would run the grep even when the LHS is false.
# The If + Proj the effect path already builds is the right shape.
subtest 'a loop in an and-arm runs on the guarded Proj, not beside the branch' => sub {
    my $g = translate('sub { my @f = (1,2); if (!$ENV{NO_SLEEP} and grep { $_ } @f) { print "s\n" } 1 }');

    my ($loop) = nodes_of($g, 'Loop');
    ok $loop, 'the grep built a Loop' or return;

    my $ctrl = $loop->control_in;
    ok defined $ctrl, 'the Loop is control-pinned' or return;
    is $ctrl->operation, 'Proj',
        'on a Proj -- the short-circuit guard, not Start';

    my ($guard) = $ctrl->inputs->@*;
    ok $guard, 'the Proj names its branch' or return;
    is $guard->operation, 'If', 'that Proj belongs to an If';

    # The guard is the LHS alone (`!$ENV{...}`), NOT the whole And: the loop
    # must be inside the short circuit, so the If cannot depend on a value the
    # loop produces.
    isnt $guard->inputs->[1]->operation, 'And',
        'the guard is the LHS, not the And whose RHS the loop computes';

    is [forks($g)], [], 'no node but an If/Loop has two control successors';
};

# KIND B -- an exited arm still counted as a merge input.
#
#     sub f { my $g = shift;
#       if ($g) { if ($g > 1) { print "a\n"; return 1 } }
#       return 0 }
#
# Measured before the fix:
#
#     13 Print  ci=12            the inner true arm, which RETURNED
#     16 Region in=[15,13]       <- and rejoined the branch anyway
#
# Print(13) then had two control successors: the function-exit Region that
# collects the `return 1`, and this branch Region. An arm that left the
# function is not a merge input; the continue Proj is already the fall-through
# control, so nothing needs building.
subtest 'an arm that returned is not a merge input' => sub {
    my $g = translate(
        'sub { my $g = shift; if ($g) { if ($g > 1) { print "a\n"; return 1 } } return 0 }');

    my ($print) = nodes_of($g, 'Print');
    ok $print, 'the guarded print is in the graph' or return;

    my @succ = control_successors($g, $print);
    is scalar(@succ), 1,
        'the returning arm ends in exactly one place -- the function exit'
        or diag('successors = ['
                . join(' ', map { $_->id } @succ)
                . ']');

    # Every branch Region must merge the CONTINUE projections, never the arm
    # that left.
    is [forks($g)], [], 'no node but an If/Loop has two control successors';
};

# KIND B, the second half -- the FUNCTION-EXIT Region's owner and predecessors.
#
# _build_single_exit scanned the exits for "the first If found" and stamped it
# as the merge's `head`. A function-exit Region merges exits that need not be
# two arms of ONE branch, so for the nested shape above it named the INNER If
# -- which already owns the real if/else join. One If, two regions.
#
# And its `predecessors` list was all-or-nothing: a FALLTHROUGH exit's control
# is the Region where the branches rejoined, so arm_proj answers undef and the
# whole field was dropped. Deparse's _join_phis REQUIRES it -- a shape whose
# only defect was one unresolvable arm refused outright.
subtest 'the function-exit merge records predecessors and claims no wrong head' => sub {
    my $g = translate(
        'sub { my $g = shift; if ($g) { if ($g > 1) { print "a\n"; return 1 } } return 0 }');

    my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
    ok $ret, 'a Return is present' or return;
    my $exit_region = $ret->control_in;
    ok $exit_region && $exit_region->operation eq 'Region',
        'the Return sits on a merge of the two exits' or return;

    my ($phi) = grep { $_->operation eq 'Phi'
                    && $_->can('region') && $_->region
                    && $_->region->id eq $exit_region->id } $g->nodes->@*;
    ok $phi, 'the exit values merge through a Phi' or return;

    my $preds = $phi->can('predecessors') ? $phi->predecessors : undef;
    ok $preds && $preds->@*, 'the exit Phi records its predecessors'
        or diag('predecessors are absent -- _join_phis cannot pair the arms');
    is scalar($preds->@*), scalar($phi->inputs->@*),
        'one predecessor per input, so the consumer pairs by position';

    # NO If MAY OWN TWO REGIONS. `head` is a claim about which branch a merge
    # closes; the function exit closes none of them here.
    my %owned;
    for my $n ($g->nodes->@*) {
        next unless $n->operation eq 'Region';
        my $head = $n->can('head') ? $n->head : undef;
        next unless $head;
        push $owned{ $head->id }->@*, $n->id;
    }
    # THE COUNT IS PINNED so the loop below cannot run zero assertions. A
    # change that stopped wiring `head` at all would leave %owned empty and
    # every per-head check would vacuously pass -- the failure mode recorded in
    # "a refusal test must name its cause". Measured here: exactly one If (the
    # outer one) owns the real if/else join, and the function-exit Region owns
    # nothing.
    is scalar(keys %owned), 1,
        'exactly one If claims a Region -- the function exit claims none'
        or diag('owned = [' . join(' ', map { "$_ => [@{ $owned{$_} }]" }
                                       sort keys %owned) . ']');

    for my $head (sort keys %owned) {
        is scalar($owned{$head}->@*), 1,
            "$head owns exactly one Region"
            or diag("regions = [@{ $owned{$head} }]");
    }
};

done_testing();
