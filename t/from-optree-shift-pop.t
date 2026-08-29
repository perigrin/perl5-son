# ABOUTME: Tests shift/pop lowering: the removed value is stamped with the array
# ABOUTME: element type and the mutation threads through memory-SSA (is_stmt_effect).

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

sub nodes_by_op ($graph, $op) {
    return grep { $_->operation eq $op } $graph->nodes->@*;
}

subtest 'shift @arr is a memory statement effect stamped with the element type' => sub {
    my $g = translate('sub { my @q = (1, 2, 3); my $x = shift @q; $x }');
    my ($shift) = grep { ($_->name // '') eq 'shift' } nodes_by_op($g, 'Call');
    ok($shift, 'a shift Call node exists');
    ok(defined $shift->control_in,
        'shift is a statement effect (memory mutation, control_in set)');
    ok(defined $shift->stamp, 'shift result is stamped');
    is($shift->stamp->type, 'Int', 'shift of an Int array yields an Int');
    # inputs = [array, memory]; control is on control_in.
    my ($arr) = grep {
        my $r = $_->stamp ? $_->stamp->type : '';
        $_->operation eq 'ArrayRef'
    } $shift->inputs->@*;
    ok($arr, 'the array is an input to the shift Call');
};

subtest 'pop @arr is likewise a stamped memory effect' => sub {
    my $g = translate('sub { my @q = (5, 6); my $x = pop @q; $x }');
    my ($pop) = grep { ($_->name // '') eq 'pop' } nodes_by_op($g, 'Call');
    ok($pop, 'a pop Call node exists');
    ok(defined $pop->control_in, 'pop is a statement effect (control_in set)');
    is($pop->stamp->type, 'Int', 'pop of an Int array yields an Int');
};

# BARE `shift` IS `shift @_`, AND IT DRAINS @_ EXACTLY LIKE ANY OTHER ARRAY.
#
# This subtest previously asserted the opposite -- that bare shift must NOT take
# the memory-effect path -- on the reasoning that "its operand is not an
# aggregate node". That is a description of the GATE
# (_is_aggregate_node tests for ArrayRef/HashRef, and @_ arrives as an
# ArgsSource stamped `Array`), not of the semantics. Perl drains @_; the IR must
# say so.
#
# THE GAP WAS A MISCOMPILE, not an imprecision. `sub { my $a = shift; my $b =
# shift; $a - $b }` built TWO Call nodes with identical inputs, no memory input
# and no control edge -- nothing ordering them and nothing distinguishing them.
# Called as f(9,4) perl prints 5; two interchangeable nodes permit 0.
subtest 'bare shift (from @_) drains @_ as a memory effect' => sub {
    my $g = translate('sub { my $x = shift; $x }');
    my ($shift) = grep { ($_->name // '') eq 'shift' } nodes_by_op($g, 'Call');
    ok($shift, 'a bare shift Call node exists');
    ok(defined $shift->control_in,
        'bare shift IS a statement effect -- it mutates @_');
    my ($args) = grep { $_->operation eq 'ArgsSource' } $shift->inputs->@*;
    ok($args, 'the ArgsSource is an input to the shift Call');
};

# THE ORDERING IS THE POINT. Two shifts in one sub must be DISTINCT nodes on the
# memory chain, each observing the array state at its own program point --
# exactly as two element reads either side of a store do.
subtest 'two bare shifts are ordered against each other' => sub {
    my $g = translate('sub { my $a = shift; my $b = shift; $a - $b }');
    my @shifts = grep { ($_->name // '') eq 'shift' } nodes_by_op($g, 'Call');
    is(scalar @shifts, 2, 'both shifts are present');

    my %mem_input;
    for my $s (@shifts) {
        my ($mem) = grep { $_->operation ne 'ArgsSource' } $s->inputs->@*;
        ok($mem, 'each shift takes a memory input') or next;
        $mem_input{ $s->id } = $mem->id;
    }
    my @mems = values %mem_input;
    is(scalar @mems, 2, 'both shifts recorded a memory input') or return;
    isnt($mems[0], $mems[1],
        'the two shifts observe DIFFERENT memory versions (the second sees the drain)');
};

# BILATERAL: a sub that does NOT touch @_ must not acquire a spurious memory
# effect, or the fix would be indistinguishable from marking every Call a
# statement effect.
subtest 'a sub that never shifts gains no @_ memory effect' => sub {
    my $g = translate('sub { my $x = 41; $x + 1 }');
    my @shifts = grep { ($_->name // '') eq 'shift' } nodes_by_op($g, 'Call');
    is(scalar @shifts, 0, 'no shift Call is invented');
};

# THE ELEMENT TYPE IS UNKNOWABLE FROM @_ ALONE, AND THE RESULT IS STILL A
# SCALAR. `shift` removes and returns ONE element, so whatever the caller passed,
# the result holds a scalar. _array_element_stamp declines here (it reads an
# ArrayRef's own inputs, and an ArgsSource has none), which is a reason to stop
# NARROWING, not a reason to answer nothing: chalk compiles ahead of time, so an
# Unknown is a hole in the emitted program rather than a missing annotation.
#
# Asserted on the WIRE rather than here: the floor runs after B::SoN's stamping
# fixpoint converges, so that anything able to narrow further gets to speak
# first. See t/wire-shift-stamp.t.

# A WHOLE-ARRAY READ AFTER A DRAIN STILL SEES THE UNDRAINED ARRAY.
#
# `sub { my $h = shift; scalar(@_) }` called with (10,1,2,3) is 3 under perl and
# 4 here: the Length reads the ArgsSource DIRECTLY rather than the shift's
# memory version. ELEMENT reads thread memory (each Subscript takes the current
# memory as a third input, so pre- and post-store reads are distinct nodes); a
# whole-array read takes the container node alone and so observes no mutation.
#
# PRE-EXISTING, and this probe reads WORSE before bare shift became a memory
# effect: the shift was then entirely unpinned and dangling, so a full-length
# @_ was at least consistent with a drain that never executed. Now the drain is
# correctly ordered and the stale read is the only thing left wrong. Recorded
# as a failing expectation rather than left silent.
subtest 'a whole-array read observes a preceding drain' => sub {
    my $g = translate('sub { my $h = shift; scalar(@_) }');
    my ($len) = nodes_by_op($g, 'Length');
    ok($len, 'the Length node exists') or return;

    my ($shift) = grep { ($_->name // '') eq 'shift' } nodes_by_op($g, 'Call');
    ok($shift, 'the shift exists') or return;

    todo 'a whole-array read takes the container, not the memory version' => sub {
        my %reaches;
        my @queue = $len->inputs->@*;
        while (my $n = shift @queue) {
            next unless defined $n;
            $reaches{ $n->id } = 1;
            push @queue, $n->inputs->@*;
        }
        ok($reaches{ $shift->id },
            'the Length reads through the shift, so it counts the drained array');
    };
};

done_testing;
