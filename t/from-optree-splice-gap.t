# ABOUTME: splice mutates its array's length, and a later count must observe it.
# ABOUTME: Was a GAP until whole-aggregate reads became memory-dependent.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree;

# THIS REFUSED UNTIL THE READ SIDE COULD SEE A MUTATION. splice shrinks (or
# grows) @a, and the Call built for it was not threaded onto @a's memory
# version, so a later `scalar @a` read the PRE-splice binding: 3, not 2. GAP
# loudly per GAP-not-miscompile was the right answer while that held.
#
# What made it unfixable from the write side was the READ: `Count` extended
# UnaryOp -- one input, no memory slot -- so it could not observe a mutation
# however well the mutation was threaded. shift/pop had the identical defect
# and SHIPPED it rather than refusing (`shift @a; scalar @a` said 3 where perl
# says 2), which is how one class came to have two answers.
#
# Count is an Access now, so splice threads memory like shift/pop and the
# count that follows reads the mutation.

sub count_of ($graph) {
    my ($count) = grep { $_->operation eq 'Count' } $graph->nodes->@*;
    return $count;
}

subtest 'splice lowers, and the count that follows is memory-dependent' => sub {
    my $sub = sub { my @a=(1,2,3); splice(@a,1,1); scalar @a };
    my $graph;
    ok(lives { $graph = SoN::FromOptree->translate($sub) },
        'translate no longer refuses a splice') or diag($@);
    return unless $graph;

    my ($splice) = grep {
        $_->operation eq 'Call' && ($_->name // '') eq 'splice'
    } $graph->nodes->@*;
    ok($splice, 'the splice is in the graph');

    # THE COUNT IS ASSERTED THROUGH THE WIRE, not here. `scalar @a` as a bare
    # coderef's trailing expression takes the return-value path, which has its
    # own defect (it returns the aggregate rather than a Count of it) that is
    # older than this change and not fixed by it. Asserting a Count here would
    # be asserting that unrelated bug is fixed. The memory-threading claim is
    # pinned in t/wire-aggregate-read-observes-mutation.t, over a whole program
    # where the read is an ordinary statement.
    is(scalar($splice->inputs->@*), 4,
        'the splice carries a memory input (array, offset, length, memory)');
};

# A 4-arg replacing splice (splice @a,$o,$l,@repl) mutates length the same way
# and takes the same path -- the arity of the CALL differs, not the effect.
subtest 'a replacing splice lowers too' => sub {
    my $sub = sub { my @a=(1,2,3); splice(@a,1,1,9,9); scalar @a };
    my $graph;
    ok(lives { $graph = SoN::FromOptree->translate($sub) },
        'a replacing splice lowers') or diag($@);
    return unless $graph;
    ok(scalar(grep { $_->operation eq 'Call' && ($_->name // '') eq 'splice' }
              $graph->nodes->@*),
        'the splice is in the graph');
};

done_testing;
