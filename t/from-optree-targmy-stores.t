# ABOUTME: Tests SoN::FromOptree TARGMY store-backs: self-assign, field write, .= append.
# ABOUTME: A TARGMY op (or an append multiconcat) writes its result back to its targ slot.

use v5.42.0;
use feature 'class';
no warnings 'experimental::class';
use Test2::V0;

use SoN::OptSuppress;
use SoN::FromOptree;

# An op with OPpTARGET_MY writes its result in-place to its targ slot -- the
# canonical shape of `$x = $x + 1` (scalar self-assign), `$n = $n + 1` (field
# write), and similar. The store-back was previously dropped (the op fell
# through to plain dispatch and the result was never rebound). `.=` is an
# APPEND multiconcat over the targ, modeled as Concat($s, lit) + rebind.

sub canonical_graph ($code) {
    SoN::OptSuppress::suppress_peep();
    my $cv = eval $code;
    my $err = $@;
    SoN::OptSuppress::restore_peep();
    die "compile failed: $err" if $err;
    return SoN::FromOptree->translate($cv);
}

sub graph_of_cv ($cv) { SoN::FromOptree->translate($cv) }

sub return_value ($graph) {
    my ($ret) = grep { $_->operation eq 'Return' } $graph->nodes->@*;
    return $ret->inputs->[-1];
}

subtest 'scalar self-assign rebinds the slot' => sub {
    my $g  = canonical_graph('sub { my $x = 5; $x = $x + 1; $x }');
    my $rv = return_value($g);
    is($rv->operation, 'Add', 'read after $x = $x + 1 is the Add (rebound value)');
    is($rv->inputs->[0]->operation, 'Constant',
        'the self-read resolved to the bound Constant(5)');
};

subtest 'append .= produces Concat and rebinds' => sub {
    my $g  = canonical_graph(q{sub { my $s = "a"; $s .= "b"; $s }});
    my $rv = return_value($g);
    is($rv->operation, 'Concat', 'read after $s .= "b" is the Concat');
    is($rv->stamp->type, 'Str', 'concat result is stamped Str');
};

subtest 'field write rebinds the field slot' => sub {
    # The store-back into a field ($n = $n + 1 in a method) is now present:
    # the Add over the FieldAccess is reachable from Return (was dropped).
    eval q{
        use feature 'class';
        no warnings 'experimental::class';
        class TargmyCounter {
            field $n :param = 0;
            method inc { $n = $n + 1 }
        }
    };
    die $@ if $@;

    my $g  = graph_of_cv(\&TargmyCounter::inc);
    my $rv = return_value($g);
    is($rv->operation, 'Add', 'the field write Add is the return value (store-back present)');
    is($rv->inputs->[0]->operation, 'FieldAccess',
        'the Add reads the field via FieldAccess');
};

done_testing();
