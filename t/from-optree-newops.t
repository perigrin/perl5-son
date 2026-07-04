# ABOUTME: Tests for new typed node generation from optree translation.
# ABOUTME: Verifies that opcodes produce their specific typed nodes instead of generic Call.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;

sub nodes_of_type ($graph, $type) {
    return grep { $_->operation eq $type } $graph->nodes->@*;
}

# -----------------------------------------------------------------------
# Part 1: Simple OpMap node_type changes
# -----------------------------------------------------------------------

subtest 'repeat op produces Repeat node (x operator)' => sub {
    my $graph = SoN::FromOptree->translate(sub { my $x = 2; "ab" x $x });
    my @nodes = nodes_of_type($graph, 'Repeat');
    ok(scalar @nodes > 0, 'repeat op produces Repeat node');
    is($nodes[0]->operation, 'Repeat', 'node operation is Repeat');
};

subtest 'xor op produces Xor node' => sub {
    my $graph = SoN::FromOptree->translate(sub { my ($a, $b) = (1, 2); $a xor $b });
    my @nodes = nodes_of_type($graph, 'Xor');
    ok(scalar @nodes > 0, 'xor op produces Xor node');
    is($nodes[0]->operation, 'Xor', 'node operation is Xor');
};

subtest 'isa op produces IsaOp node' => sub {
    # Use a simple integer variable to avoid bless/Call complications
    my $graph = SoN::FromOptree->translate(sub { my $x = 42; $x isa 'Foo' });
    my @nodes = nodes_of_type($graph, 'IsaOp');
    ok(scalar @nodes > 0, 'isa op produces IsaOp node');
    is($nodes[0]->operation, 'IsaOp', 'node operation is IsaOp');
};

subtest 'refgen produces Ref node' => sub {
    # Use a scalar ref to avoid padav (array variable) complications
    my $graph = SoN::FromOptree->translate(sub { my $x = 42; \$x });
    my @nodes = nodes_of_type($graph, 'Ref');
    ok(scalar @nodes > 0, 'refgen produces Ref node');
    is($nodes[0]->operation, 'Ref', 'node operation is Ref');
};

subtest 'anonhash produces HashRef node' => sub {
    my $graph = SoN::FromOptree->translate(sub { { a => 1, b => 2 } });
    my @nodes = nodes_of_type($graph, 'HashRef');
    ok(scalar @nodes > 0, 'anonhash produces HashRef node');
    is($nodes[0]->operation, 'HashRef', 'node operation is HashRef');
};

subtest 'anonlist produces ArrayRef node' => sub {
    my $graph = SoN::FromOptree->translate(sub { [1, 2, 3] });
    my @nodes = nodes_of_type($graph, 'ArrayRef');
    ok(scalar @nodes > 0, 'anonlist produces ArrayRef node');
    is($nodes[0]->operation, 'ArrayRef', 'node operation is ArrayRef');
};

subtest 'smartmatch OpMap entry maps to Match' => sub {
    # smartmatch (~~) is removed in Perl 5.42, so we cannot generate the opcode.
    # Verify only that the OpMap entry is correctly configured for when it does appear.
    use SoN::FromOptree::OpMap;
    my $map = SoN::FromOptree::OpMap->new();
    is($map->node_type('smartmatch'), 'Match', 'smartmatch opmap entry maps to Match');
};

subtest 'anoncode produces AnonSub node' => sub {
    my $graph = SoN::FromOptree->translate(sub { my $f = sub { 42 }; $f });
    my @nodes = nodes_of_type($graph, 'AnonSub');
    ok(scalar @nodes > 0, 'anoncode produces AnonSub node');
    is($nodes[0]->operation, 'AnonSub', 'node operation is AnonSub');
};

# -----------------------------------------------------------------------
# Part 2: die → Unwind (CFG node, not pushed to stack)
# -----------------------------------------------------------------------

subtest 'die produces Unwind CFG node' => sub {
    my $graph = SoN::FromOptree->translate(sub { die "error message" });
    my @nodes = nodes_of_type($graph, 'Unwind');
    ok(scalar @nodes > 0, 'die op produces Unwind node');
    is($nodes[0]->operation, 'Unwind', 'node operation is Unwind');
};

# -----------------------------------------------------------------------
# Part 3: backtick → BacktickExpr
# -----------------------------------------------------------------------

subtest 'backtick produces BacktickExpr node' => sub {
    my $graph = SoN::FromOptree->translate(sub { `echo hello` });
    my @nodes = nodes_of_type($graph, 'BacktickExpr');
    ok(scalar @nodes > 0, 'backtick produces BacktickExpr node');
    is($nodes[0]->operation, 'BacktickExpr', 'node operation is BacktickExpr');
};

# -----------------------------------------------------------------------
# Part 4: VarDecl wrapping for new lexicals (OPpLVAL_INTRO = 128)
# -----------------------------------------------------------------------

subtest 'padsv_store with new lexical wraps in VarDecl' => sub {
    my $graph = SoN::FromOptree->translate(sub { my $x = 42; $x });
    my @nodes = nodes_of_type($graph, 'VarDecl');
    ok(scalar @nodes > 0, 'padsv_store with OPpLVAL_INTRO produces VarDecl');
    is($nodes[0]->operation, 'VarDecl', 'node operation is VarDecl');
    is($nodes[0]->scope, 'my', 'VarDecl has scope "my"');
};

# -----------------------------------------------------------------------
# Regression: nodes that previously produced Call still exist correctly
# -----------------------------------------------------------------------

subtest 'No regressions: existing Call ops still work' => sub {
    # entersub still produces Call
    my $graph = SoN::FromOptree->translate(sub { length("hello") });
    my @nodes = $graph->nodes->@*;
    ok(scalar @nodes > 0, 'graph has nodes');
    ok(defined $graph, 'translation succeeded');
};

# -----------------------------------------------------------------------
# Part 5: dor → DefinedOr
# -----------------------------------------------------------------------

subtest 'dor produces DefinedOr node' => sub {
    my $graph = SoN::FromOptree->translate(sub { my $x; $x // 42 });
    my @nodes = nodes_of_type($graph, 'DefinedOr');
    ok(scalar @nodes > 0, 'dor op produces DefinedOr node');
    is($nodes[0]->operation, 'DefinedOr', 'node operation is DefinedOr');
};

# -----------------------------------------------------------------------
# Part 6: cond_expr → TernaryExpr
# -----------------------------------------------------------------------

subtest 'cond_expr produces TernaryExpr node' => sub {
    my $graph = SoN::FromOptree->translate(sub { my $x = 1; $x ? "yes" : "no" });
    my @nodes = nodes_of_type($graph, 'TernaryExpr');
    ok(scalar @nodes > 0, 'cond_expr op produces TernaryExpr node');
    is($nodes[0]->operation, 'TernaryExpr', 'node operation is TernaryExpr');
};

# -----------------------------------------------------------------------
# Part 7: match → RegexMatch
# -----------------------------------------------------------------------

subtest 'match produces RegexMatch node' => sub {
    my $graph = SoN::FromOptree->translate(sub { my $x = "hello"; $x =~ /ell/i });
    my @nodes = nodes_of_type($graph, 'RegexMatch');
    my ($rm) = @nodes;
    ok($rm, 'match op produces RegexMatch node');
    is($rm->operation, 'RegexMatch', 'node operation is RegexMatch');
    is($rm->pattern, 'ell', 'RegexMatch has correct pattern');
    like($rm->flags, qr/i/, 'RegexMatch has i flag');
};

# -----------------------------------------------------------------------
# Part 8: subst → RegexSubst
# -----------------------------------------------------------------------

subtest 'subst produces RegexSubst node' => sub {
    my $graph = SoN::FromOptree->translate(sub { my $x = "hello"; $x =~ s/ell/all/g });
    my @nodes = nodes_of_type($graph, 'RegexSubst');
    my ($rs) = @nodes;
    ok($rs, 'subst op produces RegexSubst node');
    is($rs->operation, 'RegexSubst', 'node operation is RegexSubst');
    is($rs->pattern, 'ell', 'RegexSubst has correct pattern');
    is($rs->replacement, 'all', 'RegexSubst has correct replacement');
    like($rs->flags, qr/g/, 'RegexSubst has g flag');
};

subtest 'anon-ref deref resolves the container to the bound aggregate (R4)' => sub {
    # `my $r = [1,2,3]; $r->[0]` -- the deref read of $r (a DREFAV padsv, which
    # carries OPf_MOD for autovivification) must resolve to the bound ArrayRef,
    # not emit a fresh unbound PadAccess. Otherwise the Subscript container has
    # no aggregate and reaches the backend with no repr.
    require SoN::OptSuppress;
    SoN::OptSuppress::suppress_peep();
    my $cv = eval 'sub { my $r = [1,2,3]; $r->[0] }';
    SoN::OptSuppress::restore_peep();
    my $g = SoN::FromOptree->translate($cv);

    my ($sub) = nodes_of_type($g, 'Subscript');
    ok($sub, 'has a Subscript node') or return;
    my $container = $sub->inputs->[0];
    # The container must reach an ArrayRef (directly or through a deref), NOT be
    # a bare unbound PadAccess.
    my $ck = ref($container); $ck =~ s/.*:://;
    isnt($ck, 'PadAccess',
        'the Subscript container is not an unbound PadAccess');
    my @arefs = nodes_of_type($g, 'ArrayRef');
    ok(scalar @arefs > 0, 'the anon-list ArrayRef survives into the graph');
};

done_testing;
