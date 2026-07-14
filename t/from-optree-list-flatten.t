# ABOUTME: A bare array variable read as a list-assignment source flattens its
# ABOUTME: elements; a scalar-context or shift/pop operand keeps the aggregate (zhi 019f5deb).

use v5.42.0;
use utf8;
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# `my @b = @a` reads @a in list context as an assignment SOURCE, so its elements
# flatten onto the stack and the aassign builds @b from the N values -- not
# ArrayRef(ArrayRef(...)), which made `scalar @b` return 1 (a silent miscompile).
# The flatten is gated on OPf_WANT_LIST + no OPf_REF/OPf_MOD + no OPpLVAL_INTRO so
# a scalar-context read (`scalar @a`, `my $n=@a`) and a shift/pop operand keep the
# aggregate.

sub translate ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub op_counts ($graph) {
    my %n;
    $n{ $_->operation }++ for $graph->nodes->@*;
    return \%n;
}

# The Return-reachable graph shape for `my @b = @a; scalar @b`: the flattened
# copy is a single ArrayRef of the 3 Constants, Length'd -- NO ArrayRef whose
# element is another ArrayRef (the pre-fix miscompile shape).
sub max_arrayref_arity ($graph) {
    my $max = 0;
    for my $n ($graph->nodes->@*) {
        next unless $n->operation eq 'ArrayRef';
        my $arity = scalar $n->inputs->@*;
        $max = $arity if $arity > $max;
    }
    return $max;
}

sub has_nested_arrayref ($graph) {
    for my $n ($graph->nodes->@*) {
        next unless $n->operation eq 'ArrayRef';
        return 1 if grep { $_->can('operation') && $_->operation eq 'ArrayRef' } $n->inputs->@*;
    }
    return 0;
}

subtest 'list-copy my @b = @a flattens (no nested ArrayRef)' => sub {
    my $g = translate('sub { my @a = (1, 2, 3); my @b = @a; scalar @b }');
    ok(!has_nested_arrayref($g),
        'no ArrayRef(ArrayRef(...)) -- the source array flattened')
        or diag('ops: ' . join(',', sort keys op_counts($g)->%*));
    is(max_arrayref_arity($g), 3, 'the copied array has all 3 elements');
};

subtest 'list literal (@a, 4) flattens the array and appends the scalar' => sub {
    my $g = translate('sub { my @a = (1, 2, 3); my @b = (@a, 4); scalar @b }');
    ok(!has_nested_arrayref($g), 'no nested ArrayRef in the flattened literal');
    is(max_arrayref_arity($g), 4, 'flattened list has 4 elements (@a + 4)');
};

subtest 'two arrays (@a, @b) both flatten' => sub {
    my $g = translate('sub { my @a = (1, 2); my @b = (3, 4); my @c = (@a, @b); scalar @c }');
    ok(!has_nested_arrayref($g), 'no nested ArrayRef in the two-array flatten');
    is(max_arrayref_arity($g), 4, 'flattened list has 4 elements');
};

subtest 'scalar context does NOT flatten (keeps the aggregate for Length)' => sub {
    # `scalar @a` and `my $n = @a` are OPf_WANT_SCALAR: the array stays an
    # aggregate a Length counts. The flatten must not fire.
    my $g = translate('sub { my @a = (1, 2, 3); scalar @a }');
    my $c = op_counts($g);
    ok($c->{Length}, 'scalar @a produces a Length over the aggregate')
        or diag('ops: ' . join(',', sort keys %$c));
    my $g2 = translate('sub { my @a = (1, 2, 3); my $n = @a; $n }');
    ok(op_counts($g2)->{Length}, 'my $n = @a produces a Length (count), not a flatten');
};

subtest 'shift/pop operand does NOT flatten (keeps the ArrayRef for the builtin)' => sub {
    # `shift @q` reads @q with OPf_REF|OPf_MOD -- the builtin needs the aggregate,
    # not its flattened elements. The flatten must not fire (it did in a first cut,
    # regressing shift/pop to "operand is not an Array/ArrayRef").
    my $g = translate('sub { my @q = (1, 2, 3); shift @q }');
    my $c = op_counts($g);
    ok($c->{Call}, 'shift @q still lowers as a builtin Call over the array')
        or diag('ops: ' . join(',', sort keys %$c));
    ok(!has_nested_arrayref($g), 'and the array is not wrapped');
};

done_testing();
