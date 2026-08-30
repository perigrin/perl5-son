# ABOUTME: An element count is not a string length -- `scalar(@a)` and
# ABOUTME: `length($s)` are different operations and must not share a node.
use v5.42.0;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

sub graph_of ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub ops_of ($g, $op) { return grep { $_->operation eq $op } $g->nodes->@* }

# THE CONFLATION. One node named `Length` served two unrelated operations:
#
#   length($s)    perl's `length` op -- BYTES in a string
#   scalar(@a)    no length op at all -- the producer SYNTHESISES a count
#
# Perl does not conflate them. `length` is its own op and only ever takes a
# string; `scalar(@a)` compiles to a bare padav in scalar context. Only one of
# the six Length construction sites came from perl's length op; the other five
# synthesise a count from scalar(@a), $#a, `$n = @a`, and foreach bounds.
#
# The producer already KNEW they differ -- every aggregate site is guarded by
# _is_aggregate_node, and FromOptree's own comment gives the stakes: wrapping a
# non-aggregate "would take a string byte-length -- a miscompile". The guard
# was doing structurally what the node name denied.
#
# It also made the type table lie. TypeLibrary can hold one operand
# requirement per op, and `Length => operands ['Str']` is right for perl's
# length and wrong for all five count sites -- so every array count read as a
# type error against its own signature.
subtest 'a string length is a Length' => sub {
    my $g = graph_of('sub { my $s = "abc"; length($s) }');
    my @len = ops_of($g, 'Length');
    is(scalar @len, 1, 'one Length node') or return;
    is($len[0]->stamp->type, 'Int', 'it yields an Int');
    is(scalar(ops_of($g, 'Count')), 0, 'and no Count node is built');
};

subtest 'an element count is a Count' => sub {
    my $g = graph_of('sub { my @a = (1,2,3); scalar(@a) }');
    my @count = ops_of($g, 'Count');
    is(scalar @count, 1, 'one Count node') or return;
    is($count[0]->stamp->type, 'Int', 'it yields an Int');
    is(scalar(ops_of($g, 'Length')), 0, 'and no Length node is built');
};

# THE POINT, stated as the thing that was impossible before: the two must be
# DISTINGUISHABLE. Asserting each in isolation would pass if both still built
# the same node, so compare the two graphs directly.
subtest 'the two are distinguishable' => sub {
    my $gs = graph_of('sub { my $s = "abc"; length($s) }');
    my $ga = graph_of('sub { my @a = (1,2,3); scalar(@a) }');
    my ($s) = ops_of($gs, 'Length');
    my ($a) = ops_of($ga, 'Count');
    ok($s && $a, 'both nodes exist') or return;
    isnt($s->operation, $a->operation,
        'a string length and an element count do NOT share an operation');
};

# THE OTHER FOUR SYNTHESIS SITES, each of which is a count and none of which
# comes from perl's length op.
subtest 'scalar-context assignment of an array is a Count' => sub {
    my $g = graph_of('sub { my @a = (1,2,3); my $n = @a; $n }');
    is(scalar(ops_of($g, 'Count')),  1, '`my $n = @a` builds a Count');
    is(scalar(ops_of($g, 'Length')), 0, 'and not a Length');
};

subtest 'the last-index form is a Count too (minus one)' => sub {
    # $#a is Count - 1. The node underneath is still a count, not a length.
    my $g = graph_of('sub { my @a = (1,2,3); $#a }');
    is(scalar(ops_of($g, 'Count')),  1, '`$#a` builds a Count underneath');
    is(scalar(ops_of($g, 'Length')), 0, 'and not a Length');
};

subtest 'a foreach bound is a Count' => sub {
    my $g = graph_of('sub { my @a = (1,2,3); my $t = 0; for my $x (@a) { $t += $x } $t }');
    ok(scalar(ops_of($g, 'Count')) >= 1, 'the loop bound is a Count');
    is(scalar(ops_of($g, 'Length')), 0, 'and no Length is built');
};

# A HASH IS COUNTED, NOT MEASURED. scalar(%h) is the key count in modern perl,
# so it is the same operation over the other aggregate kind -- one Count node
# serving both, because the T1 answer is Int either way.
subtest 'a hash in scalar context is a Count' => sub {
    my $g = graph_of('sub { my %h = (a => 1, b => 2); scalar(%h) }');
    is(scalar(ops_of($g, 'Count')),  1, 'scalar(%h) builds a Count');
    is(scalar(ops_of($g, 'Length')), 0, 'and not a Length');
};

done_testing;
