# ABOUTME: Tests for Chalk::IR::NodeFactory hash consing and node creation.
# ABOUTME: Verifies deduplication of data nodes and unique identity of CFG nodes.

use v5.42.0;
use Test2::V0;

use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Region;
use SoN::IR::Stamp;

subtest 'Identical data nodes return same instance' => sub {
    my $factory = Chalk::IR::NodeFactory->new();
    my $a = $factory->make('Constant', value => 42, stamp => SoN::IR::Stamp->new(type => 'Int'));
    my $b = $factory->make('Constant', value => 42, stamp => SoN::IR::Stamp->new(type => 'Int'));
    is($a, $b, 'same constant returns same object');
    is($a->id, $b->id, 'same id');
};

subtest 'Different data nodes return different instances' => sub {
    my $factory = Chalk::IR::NodeFactory->new();
    my $a = $factory->make('Constant', value => 42, stamp => SoN::IR::Stamp->new(type => 'Int'));
    my $b = $factory->make('Constant', value => 99, stamp => SoN::IR::Stamp->new(type => 'Int'));
    isnt($a, $b, 'different constants return different objects');
};

subtest 'CFG nodes always create new instances' => sub {
    my $factory = Chalk::IR::NodeFactory->new();
    my $a = $factory->make_cfg('Start');
    my $b = $factory->make_cfg('Start');
    isnt($a, $b, 'two Start nodes are different instances');
    ok($a->id ne $b->id, 'different IDs');
};

subtest 'Use-def chains maintained through factory' => sub {
    my $factory = Chalk::IR::NodeFactory->new();
    my $c1 = $factory->make('Constant', value => 1, stamp => SoN::IR::Stamp->new(type => 'Int'));
    my $c2 = $factory->make('Constant', value => 2, stamp => SoN::IR::Stamp->new(type => 'Int'));
    my $add = $factory->make('Add', inputs => [$c1, $c2]);

    is(scalar $c1->consumers->@*, 1, 'c1 has 1 consumer');
    is($c1->consumers->[0], $add, 'c1 consumer is add');
    is(scalar $c2->consumers->@*, 1, 'c2 has 1 consumer');
    is($add->inputs->[0], $c1, 'add left input is c1');
    is($add->inputs->[1], $c2, 'add right input is c2');
};

subtest 'Content hash is deterministic' => sub {
    my $f1 = Chalk::IR::NodeFactory->new();
    my $f2 = Chalk::IR::NodeFactory->new();

    my $a1 = $f1->make('Constant', value => 42, stamp => SoN::IR::Stamp->new(type => 'Int'));
    my $a2 = $f2->make('Constant', value => 42, stamp => SoN::IR::Stamp->new(type => 'Int'));

    # Different factory instances but same content hash
    is($a1->content_hash, $a2->content_hash, 'same content produces same hash');
};

subtest 'Constant content_hash includes const_type' => sub {
    my $factory = Chalk::IR::NodeFactory->new();

    my $int_const = $factory->make('Constant',
        value      => 42,
        const_type => 'integer',
        stamp      => SoN::IR::Stamp->new(type => 'Int'),
    );
    is($int_const->const_type, 'integer', 'const_type reader returns value');
    is($int_const->content_hash,
        'Constant|const_type=integer|value=42',
        'integer constant content_hash includes const_type');

    my $str_const = $factory->make('Constant',
        value      => 'hello',
        const_type => 'string',
        stamp      => SoN::IR::Stamp->new(type => 'Str'),
    );
    is($str_const->content_hash,
        'Constant|const_type=string|value=hello',
        'string constant content_hash includes const_type');

    my $undef_const = $factory->make('Constant',
        value      => undef,
        const_type => 'undef',
        stamp      => SoN::IR::Stamp->new(type => 'Undef'),
    );
    is($undef_const->content_hash,
        'Constant|const_type=undef|value=undef',
        'undef constant content_hash includes const_type');
};

subtest 'Constant const_type defaults to string' => sub {
    my $factory = Chalk::IR::NodeFactory->new();
    my $c = $factory->make('Constant',
        value => 'plain',
        stamp => SoN::IR::Stamp->new(type => 'Str'),
    );
    is($c->const_type, 'string', 'const_type defaults to string when omitted');
    is($c->content_hash,
        'Constant|const_type=string|value=plain',
        'default const_type appears in content_hash');
};

done_testing;
