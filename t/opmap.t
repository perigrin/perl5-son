# ABOUTME: Tests for SoN::FromOptree::OpMap opcode mapping table.
# ABOUTME: Verifies opcode lookups, stack effects, and flag detection.

use v5.42.0;
use Test2::V0;

use SoN::FromOptree::OpMap;

my $map = SoN::FromOptree::OpMap->new();

subtest 'Arithmetic ops mapped' => sub {
    is($map->node_type('add'), 'Add', 'add -> Add');
    is($map->node_type('subtract'), 'Subtract', 'subtract -> Subtract');
    is($map->node_type('multiply'), 'Multiply', 'multiply -> Multiply');
    is($map->pop_count('add'), 2, 'add pops 2');
    is($map->push_count('add'), 1, 'add pushes 1');
    is($map->pop_count('negate'), 1, 'negate pops 1');
};

subtest 'Comparison ops mapped' => sub {
    for my $op (qw(eq lt gt le ge ne ncmp)) {
        ok($map->is_known($op), "$op is known");
    }
    for my $op (qw(seq slt sgt sle sge sne scmp)) {
        ok($map->is_known($op), "$op is known");
    }
};

subtest 'Variable access mapped' => sub {
    is($map->node_type('padsv'), 'PadAccess', 'padsv -> PadAccess');
    # gv/gvsv/rv2sv are handled directly in FromOptree.pm (GV name
    # extraction; $N reads become RegexCapture) -- not in the table.
    ok(!$map->is_known('gvsv'), 'gvsv is not table-mapped (direct handler)');
};

subtest 'Call ops mapped' => sub {
    is($map->node_type('entersub'), 'Call', 'entersub -> Call');
    is($map->pop_count('entersub'), 'mark', 'entersub pops to mark');
};

subtest 'Control flow ops flagged' => sub {
    ok($map->is_branch('and'), 'and is branch');
    ok($map->is_branch('or'), 'or is branch');
    ok($map->is_branch('cond_expr'), 'cond_expr is branch');
    ok($map->is_loop('enterloop'), 'enterloop is loop');
};

subtest 'Bookkeeping ops flagged as skip' => sub {
    for my $op (qw(null pushmark enter leave nextstate)) {
        ok($map->is_skip($op), "$op is skip");
    }
};

subtest 'Unknown ops produce clear error' => sub {
    ok(!$map->is_known('nonexistent_op'), 'nonexistent op is not known');
    is($map->lookup('nonexistent_op'), undef, 'lookup returns undef');
};

done_testing;
