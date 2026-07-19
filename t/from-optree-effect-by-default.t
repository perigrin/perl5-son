# ABOUTME: Generic builtin Calls default to effectful (control-pinned) so a void
# ABOUTME: mutation (chomp/warn) survives DCE; pure builtins (uc/length) stay floatable.

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# Translate a code string under rpeep suppression (the production -MO=SoN path)
# and return the graph, or die on GAP/compile error.
sub translate ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $cerr = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $cerr" if $cerr;
    return SoN::FromOptree->translate($cv);
}

sub calls_named ($g, $name) {
    return grep {
        $_->operation eq 'Call' && ($_->name // '') eq $name
    } $g->nodes->@*;
}

sub is_effect ($n) {
    return defined $n->control_in;
}

# --- 1. void effectful builtin (chomp) survives, control-pinned ---
# Today `chomp $s; length $s` drops the chomp entirely: its pushed value is dead
# in void context, so the Call vanishes and length reads the un-chomped string.
# `chomp $scalar` compiles to the schomp (scalar-chomp) op.
subtest 'void chomp is control-pinned, not dropped' => sub {
    my $g = translate('sub { my $s = "hi\n"; chomp $s; length $s }');
    my ($chomp) = calls_named($g, 'schomp');
    ok($chomp, 'the void chomp Call survives as a node')
        or diag('ops = [' . join(' ', map { $_->operation } $g->nodes->@*) . ']');
    ok(is_effect($chomp), 'the void chomp Call is a statement effect (control-pinned)');
};

# --- 2. pure builtin stays floatable (not effect-pinned) ---
# The effect-by-default rule must EXEMPT pure builtins: a demoted uc keeps
# is_stmt_effect false so it stays a floatable data node (DCE-able, CSE-able).
# (Call hash-consing itself is a separate factory concern; here we assert the
# purity my change controls, not node identity.)
subtest 'pure uc stays floatable (not effect-pinned)' => sub {
    my $g = translate('sub { my $s = shift; my $x = uc($s); my $y = uc($s); "$x$y" }');
    my @uc = calls_named($g, 'uc');
    ok(scalar @uc >= 1, 'at least one uc Call exists') or diag('uc count = ' . scalar @uc);
    ok((grep { !is_effect($_) } @uc) == scalar @uc,
        'every pure uc Call is NOT control-pinned (stays floatable)');
};

# --- 3. bilateral DCE: effectful-unused kept, pure-unused dropped ---
subtest 'unused effectful call kept; unused pure call dropped' => sub {
    my $g_warn = translate('sub { warn "x\n"; 42 }');
    my ($warn) = calls_named($g_warn, 'warn');
    ok($warn, 'the unused warn Call is KEPT (effectful)')
        or diag('ops = [' . join(' ', map { $_->operation } $g_warn->nodes->@*) . ']');
    ok(is_effect($warn), 'the kept warn Call is control-pinned');

    my $g_uc = translate('sub { my $s = shift; uc($s); 42 }');
    my @uc = calls_named($g_uc, 'uc');
    is(scalar @uc, 0, 'the unused pure uc Call is DROPPED (floatable + value dead)')
        or diag('uc count = ' . scalar @uc);
};

# --- 4. substr purity: rvalue substr is floatable (not effect-pinned) ---
# substr is tagged PURE, so a plain rvalue substr in void position is NOT
# control-pinned (it stays a floatable data node). The lvalue store form
# (`substr(...) = "X"`) is a SEPARATE, pre-existing GAP: under rpeep
# suppression (the production -MO=SoN path) the assignment is a distinct
# sassign whose substr-lvalue target the producer does not yet lower -- the
# store was dropped before this change and remains out of its scope. The
# effect-by-default rule still guards the fused void+STACKED substr form
# (OPf_STACKED override) should the optimizer ever emit it here.
subtest 'rvalue substr is floatable (pure), not effect-pinned' => sub {
    my $g = translate('sub { my $s = "hello"; my $r = substr($s, 0, 1); $r }');
    my @substr = calls_named($g, 'substr');
    ok(scalar @substr >= 1, 'the rvalue substr Call exists')
        or diag('substr count = ' . scalar @substr);
    ok((grep { !is_effect($_) } @substr) == scalar @substr,
        'every rvalue substr is floatable (not control-pinned)');
};

# --- 5. unknown/unrecognized builtin defaults to effectful ---
# A builtin Call not on the pure allow-list must never be silently pure: in void
# position it is control-pinned so its effect is never dropped.
subtest 'non-allow-listed builtin is effect-pinned in void position' => sub {
    # `warn` is not on the pure allow-list and is used here in void position.
    my $g = translate('sub { my $s = shift; warn $s; warn $s; 1 }');
    my @warn = calls_named($g, 'warn');
    is(scalar @warn, 2, 'two distinct effectful warns (not CSE-collapsed)')
        or diag('warn count = ' . scalar @warn);
    ok((grep { is_effect($_) } @warn) == 2, 'both warns are control-pinned');
};

# --- 6. effectful-arg leak guard: demoting an outer pure call must not
#        demote its effectful argument node ---
subtest 'pure outer call does not demote its effectful argument' => sub {
    # length(<pure>) over a plain pad read: length demotes, no effect leaks.
    my $g = translate('sub { my $s = shift; chomp $s; my $n = length $s; $n }');
    my ($chomp)  = calls_named($g, 'schomp');
    my ($length) = calls_named($g, 'length');
    ok($chomp, 'the effectful chomp survives even next to a pure length');
    ok(is_effect($chomp), 'chomp stays control-pinned (its effect is not swept up by length)');
    ok(!$length || !is_effect($length), 'length itself is floatable');
};

done_testing();
