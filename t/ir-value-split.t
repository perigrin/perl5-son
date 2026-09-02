# ABOUTME: Tests the value/control split -- value nodes isa SoN::IR::Value, control nodes do not.
# ABOUTME: Mirrors chalk's Chalk::IR::Value hierarchy so `isa` is the uniform predicate on both sides.

use v5.42.0;
use Test2::V0;

use SoN::IR::Value;
use SoN::IR::NodeFactory;

# The producer had no way to ask whether a node defines a value. Fields that
# only value nodes meaningfully carry (stamp, representation) live on the base
# class, so a control node answers `undef` to a question it should not be
# askable at all -- the same three-way overload Chalk::IR::Value documents.
#
# The roster below is not invented here: it is chalk's, read off the direct
# parent of each class in lib/Chalk/IR/Node/, with identical intermediate
# parents (BinOp, UnaryOp, Access, Aggregate, Regex), so the split transfers
# exactly.
#
# 91, NOT 88: the producer declares nodes chalk does not.
#
# `Wantarray` is the newest. wantarray reports the CALLSITE's context, which
# the graph carries as the Call node's `want` -- so the callee holds the
# question and each callsite answers it, the same shape a multi-value return
# already uses. It was previously a refusal, on the grounds that a sub is
# compiled once and cannot see its callers: true of perl's INTERPRETER, and
# not binding on a graph.
# `Count` (an
# aggregate's element count) was split out of `Length` (a string's character
# count) because they are different operations that perl itself keeps apart --
# `length` is its own op taking a string, while `scalar(@a)` compiles to a bare
# padav with no length op at all. Chalk still has only `Length`, so it lowers
# `Count` by the same path until it takes the split too. The number is stated
# here rather than derived so that a class appearing or vanishing on either
# side is a red test rather than a silent drift.

my @VALUE_CLASSES = qw(
    Access Aggregate AnonSub BacktickExpr BinOp Call Coerce CompoundAssign
    Constant EnvRead ExpressionList Phi PostfixDeref Regex RegexCapture
    StructFieldAccess StructRef TernaryExpr UnaryOp
);

my @CONTROL_CLASSES = qw(
    If ListAssign Loop MemStart Print Proj Region Return Start TryCatch
    Unwind VarDecl
);

subtest 'value node classes are SoN::IR::Value' => sub {
    for my $name (@VALUE_CLASSES) {
        my $class = "SoN::IR::Node::$name";
        ok($class->isa('SoN::IR::Value'), "$name isa SoN::IR::Value");
    }
};

subtest 'control node classes are NOT SoN::IR::Value' => sub {
    # The split is only worth having if it EXCLUDES. A hierarchy where
    # everything is a Value answers every question true and distinguishes
    # nothing.
    for my $name (@CONTROL_CLASSES) {
        my $class = "SoN::IR::Node::$name";
        ok(!$class->isa('SoN::IR::Value'), "$name is not a value node");
        ok($class->isa('SoN::IR::Node'), "$name is still a SoN::IR::Node");
    }
};

subtest 'inherited leaves ride their intermediate parent' => sub {
    # Add/Concat/Divide reach Value through BinOp, Length and Count through UnaryOp,
    # PadAccess through Access. Reparenting the intermediates is what makes
    # the other 57 classes values without touching them.
    my %VIA = (
        Add        => 'BinOp',
        Concat     => 'BinOp',
        Divide     => 'BinOp',
        Length     => 'UnaryOp',
        Count      => 'UnaryOp',
        Negate     => 'UnaryOp',
        PadAccess  => 'Access',
        Parameter  => 'Access',
        ArrayLiteral   => 'Aggregate',
        RegexMatch => 'Regex',
    );
    for my $name (sort keys %VIA) {
        my $class = "SoN::IR::Node::$name";
        ok($class->isa('SoN::IR::Value'),
            "$name isa Value (via $VIA{$name})");
    }
};

subtest 'the predicate holds on real constructed nodes' => sub {
    # Class-level isa is necessary but not sufficient -- the split has to
    # survive actual construction through the factory.
    my $factory = SoN::IR::NodeFactory->new;

    my $const = $factory->make('Constant', value => 42, stamp => 'Int');
    ok($const isa SoN::IR::Value, 'a constructed Constant is a value');

    my $start = $factory->make_cfg('Start');
    ok(!($start isa SoN::IR::Value), 'a constructed Start is not a value');
    ok($start isa SoN::IR::Node, 'a constructed Start is still a Node');
};

subtest 'every node class is one or the other, never neither' => sub {
    # A class that is neither reachable as a Value nor present as a declared
    # control node is a class nobody classified -- exactly the silent state
    # this split exists to make impossible.
    my %is_control = map { $_ => 1 } @CONTROL_CLASSES;

    my $dir = 'lib/SoN/IR/Node';
    opendir(my $dh, $dir) or die "cannot read $dir: $!";
    my @names = sort map { s/\.pm$//r } grep { /\.pm$/ } readdir($dh);
    closedir $dh;

    cmp_ok(scalar @names, '==', 91, 'all 91 node classes present');

    for my $name (@names) {
        my $class = "SoN::IR::Node::$name";
        next unless $class->can('operation') || $class->isa('SoN::IR::Node');
        my $is_value = $class->isa('SoN::IR::Value');
        ok($is_value || $is_control{$name},
            "$name is classified (" . ($is_value ? 'value' : 'control') . ')');
    }
};

done_testing;
