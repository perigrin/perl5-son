# ABOUTME: An array is not a reference to one -- `my @a=(1,2,3)` and `[1,2,3]`
# ABOUTME: must not build the same node with the same stamp.
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

sub aggregates ($g) {
    return grep { $_->operation eq 'ArrayLiteral' } $g->nodes->@*;
}

# THE CONFLATION. `my @a = (1,2,3)` and `my $r = [1,2,3]` produced BYTE-IDENTICAL
# graphs -- same node type, same `ArrayRef` stamp, same inputs -- so nothing
# downstream could tell an array from a reference to one. They differ:
#
#             my @a = (1,2,3)        my $r = [1,2,3]
#   scalar    3 (a count)            an address
#   ref()     not a ref              "ARRAY"
#   storage   its own                points at someone else's
#
# The lattice already had both, on DIFFERENT branches (ArrayRef <: Ref,
# Array <: List); only the producer collapsed them. FromOptree's own comment at
# the sassign handler records the workaround this forced -- keying scalar
# context on the OP (padav vs anonlist) "NOT the value node's repr", because
# the repr could not answer.
subtest 'a plain array is stamped Array, not ArrayRef' => sub {
    my $g = translate('sub { my @a = (1,2,3); $a[0] }');
    my ($agg) = aggregates($g);
    ok($agg, 'the aggregate node exists') or return;
    is($agg->stamp->type, 'Array', 'a lexical array is an Array');
};

subtest 'an anonymous arrayref is still stamped ArrayRef' => sub {
    my $g = translate('sub { my $r = [1,2,3]; $r->[0] }');
    my ($agg) = aggregates($g);
    ok($agg, 'the aggregate node exists') or return;
    is($agg->stamp->type, 'ArrayRef', 'an anon-ref literal is a reference');
};

# THE POINT, stated as the thing that was impossible before: the two must be
# DISTINGUISHABLE. A test asserting each in isolation would pass if both were
# stamped the same, so compare them directly.
subtest 'the two are distinguishable' => sub {
    my $ga = translate('sub { my @a = (1,2,3); $a[0] }');
    my $gr = translate('sub { my $r = [1,2,3]; $r->[0] }');
    my ($arr) = aggregates($ga);
    my ($ref) = aggregates($gr);
    ok($arr && $ref, 'both aggregates exist') or return;
    isnt($arr->stamp->type, $ref->stamp->type,
        'an array and an arrayref do NOT carry the same stamp');
};

# @_ ALREADY GOT THIS RIGHT, and stays right. ArgsSource is the sub's argument
# array and was already stamped Array -- the one place the producer used the
# honest member.
subtest '@_ remains an Array' => sub {
    my $g = translate('sub { $_[0] }');
    my ($args) = grep { $_->operation eq 'ArgsSource' } $g->nodes->@*;
    ok($args, 'the ArgsSource exists') or return;
    is($args->stamp->type, 'Array', '@_ is an Array');
};

# THE EMPTY REF FORM (emptyavhv) is a SEPARATE construction site and still
# builds a reference.
subtest 'an empty anon-ref literal is still an ArrayRef' => sub {
    my $gr = translate('sub { my $r = []; $r }');
    my ($ref) = aggregates($gr);
    ok($ref, 'the empty ref node exists') or return;
    is($ref->stamp->type, 'ArrayRef', 'an empty anon-ref literal is a reference');
};

# `my @a` WITH NO INITIALIZER builds NO aggregate node at all -- just a
# PadAccess stamped Unknown, and `scalar(@a)` over it produces no Length. So it
# is not part of this split; it is its own gap, and a real one: an empty array
# has a knowable length of 0. Recorded here because a reader will otherwise
# expect the Array stamp to reach it.
subtest 'an uninitialised array has no aggregate node yet' => sub {
    my $g = translate('sub { my @a; scalar(@a) }');
    is(scalar(aggregates($g)), 0, 'no ArrayRef node is built');

    my ($pad) = grep {
        $_->operation eq 'PadAccess' && ($_->varname // '') eq '@a'
    } $g->nodes->@*;
    ok($pad, 'the pad slot exists') or return;

    todo 'an uninitialised array is a knowable empty Array, not Unknown' => sub {
        is($pad->stamp->type, 'Array', 'the pad read knows it holds an array');
    };
};

done_testing;
