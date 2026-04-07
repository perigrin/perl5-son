# ABOUTME: Tests for 3 new UnaryOp subclasses: UnaryPlus, Ref (simple),
# ABOUTME: and PostfixDeref (with $sigil field and custom content_hash).

use v5.42.0;
use Test2::V0;

use SoN::IR::Node;
use SoN::IR::Node::Constant;
use SoN::IR::Node::UnaryOp;
use SoN::IR::Stamp;

use SoN::IR::Node::UnaryPlus;
use SoN::IR::Node::Ref;
use SoN::IR::Node::PostfixDeref;

my $stamp = SoN::IR::Stamp->new(type => 'Int');

sub const ($val) {
    SoN::IR::Node::Constant->new(value => $val, stamp => $stamp)
}

# --- Simple UnaryOp subclasses ---

my @simple_cases = (
    [ 'UnaryPlus', 'SoN::IR::Node::UnaryPlus', '+' ],
    [ 'Ref',       'SoN::IR::Node::Ref',       '\\' ],
);

for my $case (@simple_cases) {
    my ($name, $class, $op) = $case->@*;
    subtest "$name is a UnaryOp" => sub {
        my $operand = const(1);
        my $node    = $class->new(inputs => [$operand]);

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
        my ($name, $class) = $case->@*;
        my $node = $class->new(inputs => [$operand]);
        my $hash = $node->content_hash;
        like($hash, qr/\Q$name\E/,             "$name content_hash contains operation name");
        like($hash, qr/\Q${\$operand->id}\E/,  "$name content_hash contains operand id");
    }
};

# --- PostfixDeref ---

subtest 'PostfixDeref is a UnaryOp with sigil field' => sub {
    my $operand = const(1);
    my $node    = SoN::IR::Node::PostfixDeref->new(
        inputs => [$operand],
        sigil  => '@',
    );

    isa_ok($node, ['SoN::IR::Node::UnaryOp'], 'PostfixDeref isa UnaryOp');
    isa_ok($node, ['SoN::IR::Node'],          'PostfixDeref isa Node');
    is($node->operand,   $operand,      'PostfixDeref->operand returns first input');
    is($node->sigil,     '@',           'PostfixDeref->sigil returns the sigil');
    is($node->operation, 'PostfixDeref','PostfixDeref->operation eq PostfixDeref');
};

subtest 'PostfixDeref content_hash includes sigil and input id' => sub {
    my $operand = const(5);

    my $array_deref = SoN::IR::Node::PostfixDeref->new(
        inputs => [$operand],
        sigil  => '@',
    );
    my $hash_deref  = SoN::IR::Node::PostfixDeref->new(
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
        $nodes{$sigil} = SoN::IR::Node::PostfixDeref->new(
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

subtest 'NodeFactory can create all 3 new unary nodes' => sub {
    use SoN::IR::NodeFactory;

    my $factory = SoN::IR::NodeFactory->new;
    my $operand = const(1);

    for my $name (qw(UnaryPlus Ref)) {
        my $node = $factory->make($name, inputs => [$operand]);
        isa_ok($node, ['SoN::IR::Node::UnaryOp'],
            "factory->make('$name') returns UnaryOp");
    }

    my $deref = $factory->make('PostfixDeref',
        inputs => [$operand],
        sigil  => '@',
    );
    isa_ok($deref, ['SoN::IR::Node::UnaryOp'],
        "factory->make('PostfixDeref') returns UnaryOp");
    is($deref->sigil, '@', "factory-made PostfixDeref has correct sigil");
};

done_testing;
