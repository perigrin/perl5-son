# ABOUTME: Tests SoN::FromOptree translates `scalar @a` / `scalar %h` to a Length node.
# ABOUTME: `scalar @a` imposes scalar context on an aggregate -> element count; `scalar $x` stays a no-op.

use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# Per corpus/mdtest/references.md R1: `scalar @a` returns the element count as an
# Int (a Length over the aggregate), NOT the aggregate itself. `scalar` is a
# context-hint no-op for a genuine scalar operand.

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

subtest '`scalar @a` is a Length over the array (R1)' => sub {
    my $g = graph_of('sub { my @a = (1, 2, 3); scalar @a }');
    my $len = node_of($g, 'Length');
    ok(defined $len, 'has a Length node') or return;
    is($len->inputs->[0]->operation, 'ArrayRef', 'Length is over the ArrayRef');
    is($len->stamp->type, 'Int', 'Length is stamped Int');
    # The Return must be wired to the Length (the count), not the ArrayRef.
    my ($ret) = $g->returns->@*;
    is($ret->inputs->[-1]->operation, 'Length',
        'Return yields the Length (element count), not the array');
};

subtest '`scalar %h` is a Length over the hash (producer)' => sub {
    # The producer emits the correct IR: Length(HashRef). NOTE the Chalk backend
    # does not yet lower Length(HashRef) (only Array/Str) -- that is an honest
    # loud GAP at lowering, not a miscompile, and is out of the R1 corpus scope
    # (R1 is `scalar @a` only). This asserts only the producer node shape.
    my $g = graph_of('sub { my %h = (a => 1, b => 2); scalar %h }');
    my $len = node_of($g, 'Length');
    ok(defined $len, 'has a Length node') or return;
    is($len->inputs->[0]->operation, 'HashRef', 'Length is over the HashRef');
};

subtest '`scalar $x` stays a no-op (teeth)' => sub {
    # A genuine scalar in scalar context is a context hint; `scalar` must not
    # wrap it in a Length (that would take the string/number length of a scalar,
    # a different op and a miscompile).
    my $g = graph_of('sub { my $x = 42; scalar $x }');
    ok(!defined node_of($g, 'Length'),
        'scalar $x does not produce a Length');
};

subtest 'a symbolic `scalar @$str` does NOT Length-wrap a scalar (teeth)' => sub {
    # `scalar @$s` where $s is a string is an invalid symbolic deref; the skipped
    # rv2av leaves a Str Constant on the stack. Length-wrapping it would take the
    # string byte-length (5 for "hello") -- a miscompile. The aggregate guard
    # must decline, leaving the scalar in place (an honest fall-through).
    my $g = graph_of('sub { my $s = "hello"; no strict "refs"; scalar @$s }');
    my $len = node_of($g, 'Length');
    ok(!defined $len || $len->inputs->[0]->operation ne 'Constant',
        'scalar @$str does not Length-wrap the scalar Constant');
};

done_testing();
