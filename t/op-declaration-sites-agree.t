# ABOUTME: An IR node OpMap can build must exist as a class, be known to the
# ABOUTME: factory, and have a type signature -- or be a documented exemption.
use v5.42.0;
use Test2::V0;

use SoN::FromOptree::OpMap;
use B::SoN::TypeLibrary;

# WHY THIS EXISTS. One operator is declared in FIVE places across four files:
#
#   OpMap.pm            optree name -> pop/node/push/flags
#   IR/Node/<Name>.pm   the node class
#   NodeFactory.pm      a `use` line AND a name in a qw() list
#   TypeLibrary.pm      operands + result
#   FromOptree.pm       %RESULT_STAMP
#
# Nothing checks that they agree, and each omission fails DIFFERENTLY and LATE.
# Adding `Count` this session updated TypeLibrary but not %RESULT_STAMP and the
# node reached the wire stamped Unknown. TypeLibrary's own header records the
# same defect from before that: "Three partial copies of one table, none of
# them labelled as such."
#
# This test does not fix the duplication -- see
# docs/plans/2026-08-31-one-operator-one-declaration.md -- it makes the
# disagreement VISIBLE and stops it widening while that work is pending.

sub nodes_opmap_can_build () {
    my %node;
    open my $fh, '<', 'lib/SoN/FromOptree/OpMap.pm' or die "open OpMap: $!";
    while (<$fh>) { $node{$1}++ if /=> \[\s*[^,]+,\s*'(\w+)'/ }
    return sort keys %node;
}

# NODES WITH NO TYPE SIGNATURE, and why. Not every node HAS operands to
# constrain -- a Constant has none, a PadAccess reads a slot. Others are simply
# undeclared and should gain a signature. Splitting them is the point: the
# first list is a design fact, the second is a TODO with a name on it.
# NODES WITH NO SIGNATURE, and why. TypeLibrary types OPERATORS: a fixed
# result, or one that is a function of the operand types. A node whose result
# depends on something the table cannot see does not belong in it, and saying
# so is the point -- an exemption with a reason is a design fact, an exemption
# without one is a TODO in disguise.

# (a) NO OPERANDS TO CONSTRAIN. A literal or a read has no inputs to derive
# from; its type comes from the syntax or the slot.
my %NO_OPERANDS_TO_DECLARE = map { $_ => 1 } qw(
    Constant PadAccess ArrayLiteral HashLiteral AnonSub Ref
);

# (b) RESULT DEPENDS ON SOMETHING THE TABLE CANNOT SEE. Not a TODO: no
# signature could be written, because the answer is not a function of operand
# TYPES.
#
#   Assign        yields its RHS -- a different type per assignment
#   Subscript     yields the container's ELEMENT type
#   Slice         yields a LIST of elements
#   Call          ~180 optree ops collapse to this one node; there is no
#                 per-builtin slot in a table keyed by node name (this is the
#                 open question behind the remaining wire Unknowns)
#   BacktickExpr  CONTEXT-SENSITIVE: Str in scalar context, List in list.
#                 perl marks it on the op (sK vs lK) and one node serves both,
#                 so a fixed signature would be right for one and wrong for the
#                 other. Stamped at the construction site instead, where the op
#                 is in hand. A signature here would be a BUG, not an
#                 improvement.
my %RESULT_NOT_A_FUNCTION_OF_OPERANDS = map { $_ => 1 } qw(
    Assign Subscript Slice Call BacktickExpr
);

subtest 'every node OpMap can build has a class file' => sub {
    my @missing = grep { ! -e "lib/SoN/IR/Node/$_.pm" } nodes_opmap_can_build();
    diag("  no lib/SoN/IR/Node/$_.pm") for @missing;
    is(\@missing, [], 'no node names a class that does not exist');
};

subtest 'every node OpMap can build is known to the factory' => sub {
    my $src = do {
        open my $fh, '<', 'lib/SoN/IR/NodeFactory.pm' or die "open factory: $!";
        local $/; <$fh>;
    };
    my @unknown = grep { $src !~ /\b\Q$_\E\b/ } nodes_opmap_can_build();
    diag("  factory does not mention $_") for @unknown;
    is(\@unknown, [], 'no node is unknown to NodeFactory');
};

# THE 47/39 GAP, pinned. Every buildable node either has a signature or is on
# one of the two lists above. A NEW node with no signature and no entry fails
# here, which is the gate: you cannot add an operator and forget its types.
subtest 'every node has a signature or a documented reason not to' => sub {
    my %sig = map { $_ => 1 } B::SoN::TypeLibrary::known_ops();
    my @undeclared = grep {
        !$sig{$_} && !$NO_OPERANDS_TO_DECLARE{$_}
                  && !$RESULT_NOT_A_FUNCTION_OF_OPERANDS{$_}
    } nodes_opmap_can_build();
    diag("  no signature and not on either list: $_") for @undeclared;
    is(\@undeclared, [],
        'no node lacks a signature without a recorded reason');
};

# THE EXEMPTION LISTS MUST NOT ROT. A node that gains a signature should leave
# the list, or the list becomes where missing declarations hide.
subtest 'the exemption lists contain only nodes that need to be there' => sub {
    my %sig = map { $_ => 1 } B::SoN::TypeLibrary::known_ops();
    my @stale = grep { $sig{$_} }
        (sort keys %NO_OPERANDS_TO_DECLARE, sort keys %RESULT_NOT_A_FUNCTION_OF_OPERANDS);
    diag("  now HAS a signature, drop from the exemption list: $_") for @stale;
    is(\@stale, [], 'no exempted node has quietly gained a signature');
};

done_testing;
