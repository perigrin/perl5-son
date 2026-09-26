# ABOUTME: Tests SoN::FromOptree translates $N capture reads, qr//, and =~ $re application.
# ABOUTME: gvsv[*N] -> RegexCapture(match, n); qr// -> Constant(regex); =~ $re -> Match(subj, qr).

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;
use JSON::PP ();
use SoN::Serialize::JSON;

# Per corpus/mdtest/host.md H1/H2 and regex.md R2:
#   - reading $1 after a match is RegexCapture(%match, n: 1) :Str
#   - qr/foo/ is a first-class matcher value: Constant(const_type 'regex')
#   - $s =~ $re applies the matcher: Match(%s, %re) :Bool (the backend
#     resolves the qr constant statically and inlines the matcher)

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

subtest '$1 after a match is RegexCapture wired to the RegexMatch (H1)' => sub {
    my $g = graph_of('sub { my $s = "ab-cd"; $s =~ /(\w+)-(\w+)/; $1 }');
    my $cap = node_of($g, 'RegexCapture');
    ok(defined $cap, 'has a RegexCapture node') or return;
    is($cap->n, 1, 'captures group 1');
    is($cap->inputs->[0]->operation, 'RegexMatch',
        'input is the preceding RegexMatch');
    is($cap->stamp->type, 'Str', 'capture is stamped Str');
};

subtest 'guarded capture in a ternary arm sees the condition match (H2)' => sub {
    my $g = graph_of('sub { my $s = "foo"; $s =~ /(o+)/ ? length($1) : 0 }');
    my $cap = node_of($g, 'RegexCapture');
    ok(defined $cap, 'has a RegexCapture node in the arm') or return;
    is($cap->inputs->[0]->operation, 'RegexMatch',
        'arm capture wired to the condition match');
};

subtest 'capture read with no preceding match is a loud GAP' => sub {
    like(dies { graph_of('sub { $1 }') },
        qr/GAP: capture/, 'dies with a GAP message, not a mystery');
};

subtest 'non-digit package scalar is a EntryDef with a name' => sub {
    my $g = graph_of('sub { our $x; $x }');
    my $sa = node_of($g, 'EntryDef');
    ok(defined $sa, 'has a EntryDef node') or return;
    is($sa->package, 'main', 'stash name extracted from the GV');
    is($sa->symbol, 'x', 'var name extracted from the GV');
};

subtest 'qr// is a Constant of const_type regex (R2)' => sub {
    my $g = graph_of('sub { my $re = qr/foo/; $re }');
    my ($const) = grep {
        $_->operation eq 'Constant' && ($_->const_type // '') eq 'regex'
    } $g->nodes->@*;
    ok(defined $const, 'has a regex Constant') or return;
    is($const->value, 'foo', 'carries the pattern');
};

subtest '=~ against a qr value is Match(subject, qr-constant) (R2)' => sub {
    my $g = graph_of(
        'sub { my $re = qr/foo/; my $s = "foobar"; $s =~ $re ? 1 : 0 }');
    my $m = node_of($g, 'Match');
    ok(defined $m, 'has a Match node') or return;
    is(scalar($m->inputs->@*), 2, 'two inputs: subject + matcher');
    is($m->inputs->[0]->value, 'foobar', 'subject is the $s binding');
    is($m->inputs->[1]->const_type, 'regex', 'matcher is the qr constant');
    is($m->stamp->type, 'Boolean', 'match result is stamped Boolean');
};

subtest 's/// rebinds the pad so a later read sees the substituted value (R3)' => sub {
    # $s =~ s/foo/baz/ is an in-place mutation of $s. A subsequent read of
    # $s must resolve to the RegexSubst result, not the pre-subst Constant.
    my $g = graph_of('sub { my $s = "foobar"; $s =~ s/foo/baz/; $s }');
    my $subst = node_of($g, 'RegexSubst');
    ok(defined $subst, 'has a RegexSubst node') or return;
    is($subst->pattern, 'foo', 'pattern extracted');
    is($subst->replacement, 'baz', 'replacement extracted');
    # s/// on a Str always yields a Str (the rewritten subject); the node must
    # carry that repr so the Chalk backend can lower it (corpus R3 :Str).
    is($subst->stamp && $subst->stamp->type, 'Str', 'RegexSubst is stamped Str');

    # THE RETURN READS THE SLOT AT THE SUBST'S MEMORY VERSION, not the subst
    # node itself. A destructive s/// on a lexical DEMOTES its slot -- the
    # value lives in memory, and a read is a location node threaded to the
    # store that produced it:
    #
    #     6 RegexSubst in=[5:PadAccess, 4:Assign]
    #     7 PadAccess  in=[6]              <- reads $s AFTER the subst
    #     8 Return     in=[7]
    #
    # Asserting `$ret->inputs->[0] == $subst` was right while the subject was a
    # folded value and the subst WAS the binding. It is stricter than the fact
    # it was protecting, which is that the return must not see the PRE-subst
    # value -- so that is what this asserts now, by walking the read back to
    # the node it observes.
    my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
    ok(defined $ret, 'has a Return node') or return;

    my $returned = $ret->inputs->[0];
    is($returned->operation, 'PadAccess',
        'the returned $s is a read of the demoted slot');
    is(($returned->inputs // [])->[0], $subst,
        '... at the memory version the substitution produced');

    # THE OBSERVED STORE IS THIS SUBSTITUTION. Without it the two assertions
    # above would pass for a read threaded to any store at all, which is the
    # shape a mis-ordered chain produces.
    #
    # This file asserts GRAPH SHAPE only. That the emitted program prints
    # `bazbar` rather than `foobar` is asserted where it can be run --
    # t/deparse-regex.t's counted-s/// round trip and
    # t/from-optree-destructive-tr-names-its-pad.t.
    is($returned->inputs->[0]->pattern, 'foo',
        'the observed store is this substitution, not an earlier one');
};

subtest 's///r is non-destructive: the source pad is NOT rebound (R3 /r)' => sub {
    # s/foo/baz/r returns a NEW string and leaves $s unchanged. A later read
    # of $s must resolve to the original Constant, not the RegexSubst result.
    my $g = graph_of(
        'sub { my $s = "foobar"; my $t = $s =~ s/foo/baz/r; $s }');
    my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
    ok(defined $ret, 'has a Return node') or return;
    my $val = $ret->inputs->[0];
    is($val->operation, 'Constant',
        'returned $s is the original Constant (/r did not rebind the pad)');
    is($val->value, 'foobar', 'and it still carries the pre-subst value');
};

subtest 's///e carries its non-foldable replacement as an operand' => sub {
    # This used to assert a GAP, on the reasoning that a replacement which does
    # not fold to a Constant cannot be resolved to a literal string -- and that
    # emitting a plausible-but-wrong RegexSubst is the dangerous RC4 class.
    #
    # That concern is unchanged and still met: the replacement is not GUESSED,
    # it is WALKED from the subst's pmreplroot subtree and hangs off the node as
    # a real operand. What was a refusal is now an honest edge.
    my $g = graph_of('sub { my $s = "foobar"; $s =~ s/foo/length($s)/e; $s }');
    my ($rs) = grep { $_->operation eq 'RegexSubst' } $g->nodes->@*;
    ok(defined $rs, 'a RegexSubst is built rather than refused') or return;
    # A destructive s/// advances the memory chain and carries the version it
    # supersedes as a TRAILING input. That edge is not an operand, and this
    # assertion is about operands -- counting raw inputs made it off by one
    # the moment the edge landed.
    # Checked by ROLE rather than by an allow-list of node classes: a list
    # naming only the kinds seen today passes by accident when the chain grows
    # a new memory point, and a memory input is exactly a node the memory
    # chain threads through.
    #
    # THE WARNING ABOVE CAME TRUE, which is why this reads a SET rather than
    # one class. `MemStart` was the only memory point a subst's trailing edge
    # ever named -- until a destructive s/// on a lexical began demoting its
    # slot, at which point the version it supersedes is the `Assign` that
    # stored into it. The assertion went off by one and reported 3 operands.
    #
    # The set is the deparser's own (`_is_memory`): a node that ADVANCES memory
    # is MemStart, EntryWrite, CellWrite, Delete or Assign. Naming it here
    # duplicates that fact, so it is spelled as the same list rather than as a
    # fresh guess about which kinds can appear.
    my $MEMORY = qr/\A SoN::IR::Node::
                    (?: MemStart | EntryWrite | CellWrite | Delete | Assign )
                    \z/x;
    my @operands = $rs->inputs->@*;
    pop @operands if @operands && ref($operands[-1]) =~ $MEMORY;
    is(scalar(@operands), 2, 'subject and computed replacement');
    ok(!grep({ ref($_) =~ $MEMORY } @operands),
        'and no memory node is left among the operands');
    is($rs->replacement, '',
        'the literal-replacement field stays empty -- no guessed string');
};

subtest 'RegexCapture and Match survive the JSON seam' => sub {
    my $g = graph_of('sub { my $s = "ab-cd"; $s =~ /(\w+)-(\w+)/; $1 }');
    my $json = SoN::Serialize::JSON::to_json({ 'main::t' => $g });
    my $data = JSON::PP->new->decode($json);
    my ($cap) = grep { $_->{op} eq 'RegexCapture' }
        $data->{methods}{'main::t'}{nodes}->@*;
    ok(defined $cap, 'RegexCapture serialized') or return;
    is($cap->{fields}{n}, 1, 'n field serialized');
};

done_testing();
