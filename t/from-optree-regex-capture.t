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

subtest 'non-digit package scalar is a StashAccess with a name' => sub {
    my $g = graph_of('sub { our $x; $x }');
    my $sa = node_of($g, 'StashAccess');
    ok(defined $sa, 'has a StashAccess node') or return;
    is($sa->stash_name, 'main', 'stash name extracted from the GV');
    is($sa->var_name, 'x', 'var name extracted from the GV');
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

    my ($ret) = grep { $_->operation eq 'Return' } $g->nodes->@*;
    ok(defined $ret, 'has a Return node') or return;
    is($ret->inputs->[0], $subst,
        'the returned $s is the RegexSubst result, not the pre-subst Constant');
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

subtest 's///e non-foldable replacement is a loud GAP, not silent garbage' => sub {
    # s/foo/CODE/e (and any replacement that does not fold to a Constant)
    # cannot be resolved to a literal string. Rather than emit a plausible
    # but wrong RegexSubst (the dangerous RC4 class), the producer must die
    # loudly so the miscompile is visible.
    like(
        dies { graph_of('sub { my $s = "foobar"; $s =~ s/foo/length($s)/e; $s }') },
        qr/GAP.*subst.*replacement|replacement.*not.*literal|GAP/,
        'dies with a GAP for a non-literal replacement',
    );
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
