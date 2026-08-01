# ABOUTME: Tests for 3 UnaryOp subclasses: UnaryPlus, Ref (simple),
# ABOUTME: and PostfixDeref (with $sigil field and custom content_hash).

use v5.42.0;
use Test2::V0;

use SoN::IR::NodeFactory;
use SoN::IR::Stamp;

my $factory = SoN::IR::NodeFactory->new;
my $stamp = SoN::IR::Stamp->new(type => 'Int');

# Nodes are built through the factory, not by direct ->new: SoN::IR::Node
# requires an explicit content-hash id that only the factory assigns
# (SoN::IR::Node auto-generated one; SoN::IR::Node does not).
sub const ($val) {
    $factory->make('Constant', value => $val, stamp => $stamp)
}

# --- Simple UnaryOp subclasses ---

my @simple_cases = (
    [ 'UnaryPlus', '+' ],
    [ 'Ref',       '\\' ],
);

for my $case (@simple_cases) {
    my ($name, $op) = $case->@*;
    subtest "$name is a UnaryOp" => sub {
        my $operand = const(1);
        my $node    = $factory->make($name, inputs => [$operand]);

        isa_ok($node, ['SoN::IR::Node::UnaryOp'], "$name isa UnaryOp");
        isa_ok($node, ['SoN::IR::Node'],          "$name isa Node");
        is($node->operand,   $operand, "$name->operand returns first input");
        is($node->op_str,    $op,      "$name->op_str eq '$op'");
        is($node->operation, $name,    "$name->operation eq '$name'");
    };
}

# --- Simple UnaryOp content_hash includes operation name and input id ---

subtest 'simple UnaryOp content_hash includes operation name and input id' => sub {
    my $operand = const(42);

    for my $case (@simple_cases) {
        my ($name) = $case->@*;
        my $node = $factory->make($name, inputs => [$operand]);
        my $hash = $node->content_hash;
        like($hash, qr/\Q$name\E/,             "$name content_hash contains operation name");
        like($hash, qr/\Q${\$operand->id}\E/,  "$name content_hash contains operand id");
    }
};

# --- PostfixDeref ---

subtest 'PostfixDeref is a Node with sigil field' => sub {
    # SoN::IR::Node::PostfixDeref inherits directly from SoN::IR::Node
    # rather than UnaryOp and has no operand() accessor -- unlike
    # SoN::IR::Node::PostfixDeref, which modeled it as a UnaryOp. Read the
    # operand via inputs() instead.
    my $operand = const(1);
    my $node    = $factory->make('PostfixDeref',
        inputs => [$operand],
        sigil  => '@',
    );

    isa_ok($node, ['SoN::IR::Node'],  'PostfixDeref isa Node');
    is($node->inputs->[0], $operand,    'PostfixDeref inputs->[0] is the operand');
    is($node->sigil,     '@',           'PostfixDeref->sigil returns the sigil');
    is($node->operation, 'PostfixDeref','PostfixDeref->operation eq PostfixDeref');
};

subtest 'PostfixDeref content_hash includes sigil and input id' => sub {
    my $operand = const(5);

    my $array_deref = $factory->make('PostfixDeref',
        inputs => [$operand],
        sigil  => '@',
    );
    my $hash_deref  = $factory->make('PostfixDeref',
        inputs => [$operand],
        sigil  => '%',
    );

    my $hash_array = $array_deref->content_hash;
    my $hash_hash  = $hash_deref->content_hash;

    like($hash_array, qr/PostfixDeref/,           'content_hash contains PostfixDeref');
    like($hash_array, qr/sigil=@/,                'content_hash for @ contains sigil=@');
    like($hash_hash,  qr/sigil=%/,                'content_hash for % contains sigil=%');
    like($hash_array, qr/\Q${\$operand->id}\E/,   'content_hash contains operand id');
    isnt($hash_array, $hash_hash, 'different sigils produce different content hashes');
};

subtest 'PostfixDeref content_hash differentiates all four sigils' => sub {
    my $operand = const(7);

    my %nodes;
    for my $sigil (qw(@ % $ &)) {
        $nodes{$sigil} = $factory->make('PostfixDeref',
            inputs => [$operand],
            sigil  => $sigil,
        );
    }

    my %hashes = map { $_ => $nodes{$_}->content_hash } keys %nodes;

    for my $sigil (qw(@ % $ &)) {
        for my $other (qw(@ % $ &)) {
            next if $sigil eq $other;
            isnt($hashes{$sigil}, $hashes{$other},
                "sigil $sigil and $other produce different content hashes");
        }
    }
};

# --- NodeFactory registration ---

subtest 'NodeFactory can create all 3 unary nodes' => sub {
    my $operand = const(1);

    for my $name (qw(UnaryPlus Ref)) {
        my $node = $factory->make($name, inputs => [$operand]);
        isa_ok($node, ['SoN::IR::Node::UnaryOp'],
            "factory->make('$name') returns UnaryOp");
    }

    # PostfixDeref is not a UnaryOp under SoN::IR (see the "isa Node"
    # comment above) -- only assert it's a Node with the right sigil.
    my $deref = $factory->make('PostfixDeref',
        inputs => [$operand],
        sigil  => '@',
    );
    isa_ok($deref, ['SoN::IR::Node'],
        "factory->make('PostfixDeref') returns a Node");
    is($deref->sigil, '@', "factory-made PostfixDeref has correct sigil");
};

done_testing;
