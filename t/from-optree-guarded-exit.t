# ABOUTME: Tests SoN::FromOptree control polarity for statement-modifier guarded exits.
# ABOUTME: `return X if C` (C and return) vs `return X unless C` (C or return) branch oppositely.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;

# The EXIT must land on the If's TRUE branch (Proj index 0) for BOTH idioms, so
# it aligns with the exit value in the single-exit Phi (the backend wires Phi
# arm 0 = then/true, and _build_single_exit records the exit value FIRST). So
# the CONTINUATION (guard not taken) is always the FALSE branch -> Proj index 1.
#
# `return X if C` compiles to `C and return X`: the exit fires when C is TRUE, so
# C already IS the exit condition -> If(C), exit on the TRUE branch, continue on
# index 1.  `return X unless C` compiles to `C or return X`: the exit fires when
# C is FALSE, so the exit condition is Not(C) -> If(Not(C)), exit on the TRUE
# branch, continue on index 1.  A handler that continued `unless` on the TRUE
# proj (index 0) without negating the condition put the exit value (Phi arm 0)
# on the true branch while the exit actually fired on the false branch -- an
# inverted polarity that miscompiled (`return 99 unless $e>3` with $e<=3
# returned the fall-through instead of 99). zhi 019f26a5.

# Find the Proj that feeds the continuation's control chain: the guard's If has
# two Projs; the one whose consumer is NOT the recorded return exit is the
# continuation. We assert on the Proj index that the main (post-guard) control
# threads through.
sub continuation_proj_index ($code) {
    my $cv = eval $code;
    die "compile failed: $@" if $@;
    my $g = SoN::FromOptree->translate($cv);
    my ($if) = grep { $_->operation eq 'If' } $g->nodes->@*;
    return undef unless $if;
    my @projs = grep {
        $_->operation eq 'Proj'
            && $_->inputs->@* && $_->inputs->[0] == $if
    } $g->nodes->@*;
    # The continuation Proj is the one that some non-Return node builds on, OR
    # the one set as control for the trailing statement. Simplest robust check:
    # the exit's control edge is the OTHER proj. Identify the return exit's
    # control, then the continuation proj is the one that is NOT it.
    my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
    # The single-exit Region merges both control edges; find the proj that is
    # NOT an input (directly or via Region) to the returned exit for the guarded
    # arm. Fall back: return the index of the proj set as sim control -- which is
    # the one threaded to op->next. We detect it as the proj with no Return/Unwind
    # consumer among its transitive users at depth 1.
    for my $p (@projs) {
        my $feeds_exit = 0;
        for my $c ($p->consumers->@*) {
            $feeds_exit = 1 if $c->operation =~ /Return|Unwind|Region/;
        }
        return $p->index unless $feeds_exit;
    }
    return $projs[0] ? $projs[0]->index : undef;
}

subtest 'return-if (and-guard): continuation is the FALSE proj (index 1)' => sub {
    my $idx = continuation_proj_index('sub ($x) { return 1 if $x; return 2 }');
    is($idx, 1, 'and-guarded exit continues on Proj index 1 (guard false)');
};

subtest 'return-unless (or-guard): continuation is the FALSE proj (index 1)' => sub {
    my $idx = continuation_proj_index('sub ($x) { return 1 unless $x; return 2 }');
    is($idx, 1, 'or-guarded exit continues on Proj index 1 (guard not taken)');
};

# The `unless` guard negates its condition (If(Not(C))) so the exit lands on the
# TRUE branch, matching the `if` idiom and the single-exit Phi arm order.
subtest 'return-unless negates the condition (If(Not(C)))' => sub {
    my $cv = eval 'sub ($x) { return 1 unless $x; return 2 }';
    my $g  = SoN::FromOptree->translate($cv);
    my ($if) = grep { $_->operation eq 'If' } $g->nodes->@*;
    ok($if, 'an If guards the unless-exit');
    my $cond = $if->inputs->[1];
    is($cond->operation, 'Not', 'the unless guard tests Not(C), not C');
};

# `return X if C` must NOT negate -- C is already the exit condition.
subtest 'return-if does not negate the condition' => sub {
    my $cv = eval 'sub ($x) { return 1 if $x; return 2 }';
    my $g  = SoN::FromOptree->translate($cv);
    my ($if) = grep { $_->operation eq 'If' } $g->nodes->@*;
    my $cond = $if->inputs->[1];
    isnt($cond->operation, 'Not', 'the if guard uses C directly, not Not(C)');
};

done_testing();
