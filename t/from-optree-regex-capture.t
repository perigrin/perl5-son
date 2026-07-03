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
