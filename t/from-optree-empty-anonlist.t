# ABOUTME: Tests SoN::FromOptree translates an empty `[]` / `{}` (a fused emptyavhv op).
# ABOUTME: An empty anonlist/anonhash must emit an empty ArrayRef/HashRef, never a silent skip.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# Modern perl fuses an empty `my $r=[]` / `my $r={}` into a single `emptyavhv`
# op with TARGMY (it writes the empty aggregate straight into the pad slot),
# NOT an anonlist/anonhash with a pushmark. That op must translate to an empty
# ArrayRef (or HashRef for `{}`), so the enclosing sub emits normally. It
# previously built a valueless Constant and died -- an INTERNAL ERROR masked as
# a silent skip (the whole sub vanished from the output).

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub node_of ($g, $want_op) {
    my ($node) = grep { $_->operation eq $want_op } $g->nodes->@*;
    return $node;
}

# The original zhi 019f5ed3 repro: a `my $r=[]` whose ref is never used. The
# empty aggregate is DCE-dead (no consumer), so it does not appear in the graph
# -- but the SUB must still translate and return `$x`. The bug was that it died
# building a valueless Constant, so the whole sub vanished (a silent skip). This
# asserts the sub emits and returns the constant, i.e. no silent skip.
subtest 'a dead empty `[]` does not vanish the sub (no silent skip, 019f5ed3)' => sub {
    my $g = graph_of('sub { my $r = []; my $x = 1; $x }');
    ok(defined $g, 'sub translated to a graph (did not vanish)') or return;
    my ($ret) = $g->returns->@*;
    ok(defined $ret, 'sub has a Return') or return;
    is($ret->inputs->[-1]->operation, 'Constant',
        'the sub returns the constant $x (translated normally)');
};

# When the empty ref IS used, the empty aggregate is live and must be a real
# ArrayRef/HashRef with zero elements (not a Constant, not a crash).
subtest 'a live empty `[]` is an empty ArrayRef (0 elements)' => sub {
    my $g = graph_of('sub { my $r = []; scalar @$r }');
    my $aref = node_of($g, 'ArrayLiteral');
    ok(defined $aref, 'has an ArrayRef node for the empty []') or return;
    is(scalar $aref->inputs->@*, 0, 'the ArrayRef has zero elements');
};

subtest 'a live empty `{}` is an empty HashRef (0 elements)' => sub {
    my $g = graph_of('sub { my $r = {}; scalar %$r }');
    my $href = node_of($g, 'HashLiteral');
    ok(defined $href, 'has a HashRef node for the empty {}') or return;
    is(scalar $href->inputs->@*, 0, 'the HashRef has zero elements');
};

subtest 'non-empty `[1,2,3]` still builds a 3-element ArrayRef (teeth)' => sub {
    my $g = graph_of('sub { my $r = [1, 2, 3]; $r->[0] }');
    my $aref = node_of($g, 'ArrayLiteral');
    ok(defined $aref, 'has an ArrayRef node') or return;
    is(scalar $aref->inputs->@*, 3, 'the ArrayRef has 3 elements');
};

done_testing();
