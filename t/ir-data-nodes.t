# ABOUTME: Tests for data nodes, operation nodes, and access nodes.
# ABOUTME: Verifies all node types construct correctly through NodeFactory.

use v5.42.0;
use Test2::V0;

use SoN::IR::NodeFactory;
use SoN::IR::Stamp;

my $factory = SoN::IR::NodeFactory->new();
my $int_stamp = SoN::IR::Stamp->new(type => 'Int');

# Helper to make constants
sub const ($val) { $factory->make('Constant', value => $val, stamp => $int_stamp) }

subtest 'Constant and Phi' => sub {
    my $c = const(42);
    isa_ok($c, 'SoN::IR::Node');
    is($c->value, 42, 'constant value');

    my $region = $factory->make_cfg('Region');
    my $a = const(1);
    my $b = const(2);
    my $phi = $factory->make('Phi', inputs => [$a, $b], region => $region);
    is($phi->region, $region, 'phi references its region');
    is(scalar $phi->inputs->@*, 2, 'phi has 2 inputs');
};

subtest 'Arithmetic operations' => sub {
    my ($a, $b) = (const(10), const(20));
    for my $op (qw(Add Subtract Multiply Divide)) {
        my $node = $factory->make($op, inputs => [$a, $b]);
        isa_ok($node, 'SoN::IR::Node');
        is($node->operation, $op, "$op operation name");
        is(scalar $node->inputs->@*, 2, "$op has 2 inputs");
    }
    my $neg = $factory->make('Negate', inputs => [$a]);
    is($neg->operation, 'Negate', 'Negate operation');
    is(scalar $neg->inputs->@*, 1, 'Negate is unary');
};

subtest 'String operations' => sub {
    my ($a, $b) = (const('hello'), const('world'));
    my $cat = $factory->make('Concat', inputs => [$a, $b]);
    is($cat->operation, 'Concat', 'Concat operation');
    my $len = $factory->make('Length', inputs => [$a]);
    is($len->operation, 'Length', 'Length operation');
};

subtest 'Comparison operations' => sub {
    my ($a, $b) = (const(1), const(2));
    for my $op (qw(NumEq NumLt NumGt NumLe NumGe NumNe NumCmp
                   StrEq StrLt StrGt StrLe StrGe StrNe StrCmp)) {
        my $node = $factory->make($op, inputs => [$a, $b]);
        is($node->operation, $op, "$op operation");
    }
};

subtest 'Logical operations' => sub {
    my ($a, $b) = (const(1), const(0));
    for my $op (qw(And Or)) {
        my $node = $factory->make($op, inputs => [$a, $b]);
        is($node->operation, $op, "$op operation");
    }
    my $not = $factory->make('Not', inputs => [$a]);
    is($not->operation, 'Not', 'Not operation');
    my $def = $factory->make('Defined', inputs => [$a]);
    is($def->operation, 'Defined', 'Defined operation');
};

subtest 'Assign' => sub {
    my ($a, $b) = (const(1), const(2));
    my $assign = $factory->make('Assign', inputs => [$a, $b]);
    is($assign->operation, 'Assign', 'Assign operation');
};

subtest 'Call node with dispatch metadata' => sub {
    my $arg = const(42);
    my $call = $factory->make('Call',
        inputs        => [$arg],
        dispatch_kind => 'method',
        name          => 'foo',
    );
    is($call->dispatch_kind, 'method', 'dispatch kind');
    is($call->name, 'foo', 'call name');
};

subtest 'Hash consing for operations' => sub {
    my ($a, $b) = (const(1), const(2));
    my $add1 = $factory->make('Add', inputs => [$a, $b]);
    my $add2 = $factory->make('Add', inputs => [$a, $b]);
    is($add1, $add2, 'same Add with same inputs returns same instance');
};

subtest 'PadAccess' => sub {
    my $pad = $factory->make('PadAccess', targ => 3, varname => '$x');
    is($pad->targ, 3, 'pad targ');
    is($pad->varname, '$x', 'pad varname');
};

subtest 'FieldAccess' => sub {
    my $field = $factory->make('FieldAccess', field_index => 2, field_stash => 'Point');
    is($field->field_index, 2, 'field index');
    is($field->field_stash, 'Point', 'field stash');
};

subtest 'EntryDef' => sub {
    # The sigil is its own REQUIRED field, not a prefix on the name. Carrying
    # it in var_name ('$bar') left the two indistinguishable at the identity,
    # which is what let $_ and @_ hash-cons into one node.
    my $stash = $factory->make('EntryDef',
        stash_name => 'Foo', sigil => '$', var_name => 'bar');
    is($stash->stash_name, 'Foo', 'stash name');
    is($stash->sigil, '$', 'sigil');
    is($stash->var_name, 'bar', 'var name');

    # Same name, different sigil => a DIFFERENT node.
    my $arr = $factory->make('EntryDef',
        stash_name => 'Foo', sigil => '@', var_name => 'bar');
    isnt($stash->content_hash, $arr->content_hash,
        '$Foo::bar and \@Foo::bar are different variables');
};

done_testing;
