# ABOUTME: Operator signatures for the producer: what each IR op requires and yields.
# ABOUTME: A deliberate mirror of chalk's TypeLibrary, keyed by IR op name.

use v5.42.0;
use utf8;

package B::SoN::TypeLibrary;

use SoN::IR::Stamp;

# A DELIBERATE COPY, AND WHY THERE IS ONE.
#
# chalk carries this knowledge in `Chalk::Grammar::Perl::TypeLibrary` as
# `%BINARY_OP_SIGNATURES` / `%UNARY_OP_SIGNATURES`, keyed by SOURCE OPERATOR
# ('+', 'eq') with `{ left, right, result }`. The producer cannot `use` it: the
# SoN/Chalk namespace divorce means B::SoN stands alone, and a runtime
# dependency on chalk would put the producer inside the consumer.
#
# So this is a mirror, and being explicit about that is the point. It was
# previously being re-derived by accident, in pieces, in two different files:
# `%OPERAND_REQUIRES` in B/SoN.pm held the input half, `%SELF_TYPED_OPS` in
# NodeFactory held the fixed-result cases, and a third table was about to be
# added for bounded results. Three partial copies of one table, none of them
# labelled as such.
#
# KEYED BY IR OP NAME, not by source operator. chalk's `%IR_OP_SOURCE_NAME`
# translates between them for a handful of string ops; the producer only ever
# has IR op names in hand, so routing through source spellings would add a
# lookup and a partial map for nothing.
#
# WHEN CHALK'S TABLE CHANGES, THIS ONE MUST. There is no mechanism enforcing
# that -- the two repos share no code by design. What makes the divergence
# survivable is that chalk's corpus gate runs the producer's output through
# chalk's lowering: a disagreement about what an operator yields shows up as a
# behavioural mismatch rather than silently.
#
# THREE FACTS PER OPERATOR, and the earlier code conflated the last two:
#
#   operands  what the op REQUIRES of its inputs. `*` needs Num whatever
#             arrives, which is what lets a use site type an untyped operand.
#
#   result    what the op YIELDS. Either FIXED (`!$x` is Boolean however wide
#             $x is) or a CEILING (`$a * $b` is Int when both are Int, Num when
#             they are not -- never wider than Num).
#
# The distinction between fixed and ceiling is not in the table: both are just
# `result`. The CALLER decides whether to take it outright or meet the operand
# join against it, because that depends on whether the op's output varies with
# its input -- see `result_is_join` below.

# The operators whose result is the JOIN of their operands, capped by `result`.
# Everything else takes its `result` outright.
#
# Divide is deliberately NOT here: 4/2 is Int while 1/2 is not, so its result
# is not the join of its operands. It is still capped at Num.
# MEASURED AGAINST PERL, because this set disagreed with FromOptree's
# %RESULT_STAMP on five entries and perl settles every one of them:
#
#   5.7 & 3   is 1     bitwise TRUNCATES to Int whatever arrives, so the
#                      result does not vary with the operands -- not a join
#   "a" . 5   is "a5"  concat is ALWAYS Str, likewise not a join. Left here,
#                      join(Int,Int) capped at Str gave Int for `$a . $b`,
#                      which is wrong; it was masked only because
#                      %RESULT_STAMP stamps Concat during the walk and
#                      _stamp_derived fills Unknowns alone.
#   -5.5      is -5.5  negate PRESERVES its operand's type, so it IS a join
#                      (it was absent here and fixed at Num)
my %RESULT_IS_JOIN = map { $_ => 1 } qw(
    Add Subtract Multiply Negate
);

my %SIGNATURES = (
    # Arithmetic: numeric in, numeric out, never wider than Num.
    Add        => { operands => ['Num', 'Num'], result => 'Num' },
    Subtract   => { operands => ['Num', 'Num'], result => 'Num' },
    Multiply   => { operands => ['Num', 'Num'], result => 'Num' },
    Divide     => { operands => ['Num', 'Num'], result => 'Num' },
    Modulo     => { operands => ['Num', 'Num'], result => 'Int' },
    Power      => { operands => ['Num', 'Num'], result => 'Num' },
    Negate     => { operands => ['Num'],        result => 'Num' },
    UnaryPlus  => { operands => ['Num'],        result => 'Num' },

    # Numeric comparison: numeric in, Boolean out. <=> yields -1/0/1.
    NumEq      => { operands => ['Num', 'Num'], result => 'Boolean' },
    NumNe      => { operands => ['Num', 'Num'], result => 'Boolean' },
    NumLt      => { operands => ['Num', 'Num'], result => 'Boolean' },
    NumGt      => { operands => ['Num', 'Num'], result => 'Boolean' },
    NumLe      => { operands => ['Num', 'Num'], result => 'Boolean' },
    NumGe      => { operands => ['Num', 'Num'], result => 'Boolean' },
    NumCmp     => { operands => ['Num', 'Num'], result => 'Int' },

    # String: string in, string out. cmp yields -1/0/1, length a count.
    Concat     => { operands => ['Str', 'Str'], result => 'Str' },
    Repeat     => { operands => ['Str', 'Int'], result => 'Str' },
    StrEq      => { operands => ['Str', 'Str'], result => 'Boolean' },
    StrNe      => { operands => ['Str', 'Str'], result => 'Boolean' },
    StrLt      => { operands => ['Str', 'Str'], result => 'Boolean' },
    StrGt      => { operands => ['Str', 'Str'], result => 'Boolean' },
    StrLe      => { operands => ['Str', 'Str'], result => 'Boolean' },
    StrGe      => { operands => ['Str', 'Str'], result => 'Boolean' },
    StrCmp     => { operands => ['Str', 'Str'], result => 'Int' },
    Length     => { operands => ['Str'],        result => 'Int' },
    # A COUNT IS NOT A LENGTH. Length measures a string; Count counts an
    # aggregate's elements, so its operand is `List` -- the lattice parent
    # covering both Array and Hash. Sharing one entry made every array count
    # read as a type error against a signature written for strings.
    Count      => { operands => ['List'],       result => 'Int' },

    # Bitwise: integer in, integer out.
    BitAnd     => { operands => ['Int', 'Int'], result => 'Int' },
    BitOr      => { operands => ['Int', 'Int'], result => 'Int' },
    BitXor     => { operands => ['Int', 'Int'], result => 'Int' },
    LeftShift  => { operands => ['Int', 'Int'], result => 'Int' },
    RightShift => { operands => ['Int', 'Int'], result => 'Int' },
    Complement => { operands => ['Int'],        result => 'Int' },

    # Fixed result, operand unconstrained. `!$x` is Boolean however wide $x is.
    # `operands => []` means the op imposes NOTHING -- distinct from an op
    # absent from this table, about which nothing at all is known.
    Not        => { operands => [], result => 'Boolean' },
    Defined    => { operands => [], result => 'Boolean' },
    RefType    => { operands => [], result => 'Str' },
    RegexMatch => { operands => ['Str'], result => 'Boolean' },
    NotMatch   => { operands => ['Str'], result => 'Boolean' },
    IsaOp      => { operands => ['Scalar', 'Str'], result => 'Boolean' },

    # Range yields a list of integers.
    Range      => { operands => ['Int', 'Int'], result => 'List' },
);

# operand_type($ir_op, $position) -> the type this op requires of that operand,
# or undef when it imposes nothing (or the op is unknown).
# NODE-LEVEL OPERAND CONTRACTS, kept apart from %SIGNATURES on purpose.
#
# %SIGNATURES mirrors chalk's table and describes SOURCE OPERATORS: `*` needs
# Num, `eq` needs Str. This hash is for the cases where the IR NODE and the
# source builtin genuinely DISAGREE, and it has one member for the same reason
# chalk's %_NODE_OPERAND_REPR has one: the IR `Print` node lowers a single
# representation, so every argument position is Str, while perl's `print` is
# variadic over `List` because perl flattens into it. Two claims about two
# different things, and folding this into %SIGNATURES would put a node-level
# fact in the source-operator table and break the mirror.
#
# AN ENTRY THAT MERELY RESTATES A SOURCE SIGNATURE BELONGS IN %SIGNATURES. This
# is an override table for real conflicts, not a second place to write the same
# answer -- the failure mode this file's header already records ("three partial
# copies of one table, none of them labelled as such").
my %NODE_OPERAND_TYPE = (
    Print => 'Str',    # every position, however many arguments
);

# operand_type($ir_op, $position) -> what this position REQUIRES, or undef.
#
# undef is meaningful and must not become a default: a caller distinguishes
# "this position requires nothing" from "requires Str", and
# _insert_type_coercions skips a position whose requirement is undef. A default
# here would start coercing the operands of every op the tables do not describe.
sub operand_type ($ir_op, $position) {
    # The node-level contract wins where it exists: it is a fact about the node
    # this position belongs to, not about the operator it was spelled with.
    return $NODE_OPERAND_TYPE{$ir_op} if exists $NODE_OPERAND_TYPE{$ir_op};
    my $sig = $SIGNATURES{$ir_op} or return undef;
    return ( $sig->{operands} // [] )->[$position];
}

# result_type($ir_op) -> what this op yields, or undef when the op is unknown.
#
# Whether that is the answer OUTRIGHT or a CEILING to meet the operand join
# against is `result_is_join`'s question, not this one's.
sub result_type ($ir_op) {
    my $sig = $SIGNATURES{$ir_op} or return undef;
    return $sig->{result};
}

# result_is_join($ir_op) -> does this op's result VARY with its operands?
#
# True for `$a + $b` (Int when both are Int, Num otherwise); false for `$a == $b`
# (Boolean whatever arrives). A true answer means the caller should join the
# operands and MEET that against result_type; a false one means take
# result_type outright.
sub result_is_join ($ir_op) {
    return $RESULT_IS_JOIN{$ir_op} ? 1 : 0;
}

# result_for($ir_op, @operand_types) -> the type this op yields given those
# operands, or undef when the table cannot say.
#
# THIS IS THE QUESTION CALLERS ACTUALLY HAVE, and result_is_join was the wrong
# shape for it: a boolean about the CALLER'S ALGORITHM rather than an answer.
# Every consumer then reimplemented join-then-cap, and each got to make its own
# mistakes about arity -- _stamp_derived required exactly two operands, which
# made every UNARY entry in %RESULT_IS_JOIN dead. `Negate` agreed with
# FromOptree's %RESULT_STAMP on paper while being unable to fire.
#
# The rule, stated once, here:
#
#   a CONSTANT result   -> that type, whatever arrived  (Concat is Str,
#                          BitAnd is Int, NumEq is Boolean)
#   a JOIN result       -> the join of the operands, CAPPED at what the
#                          operator can yield. `Int + Int` stays Int; a join
#                          that escaped above the cap (Scalar) comes down to it
#
# Any arity. An unknown or absent operand type yields undef -- an honest
# "cannot say", never a guess.
sub result_for ($ir_op, @operands) {
    my $result = result_type($ir_op) // return undef;
    return $result unless result_is_join($ir_op);

    return undef unless @operands;
    return undef if grep { !defined || $_ eq 'Unknown' } @operands;

    my $joined = SoN::IR::Stamp->new( type => shift @operands );
    $joined = SoN::IR::Stamp::join( $joined, SoN::IR::Stamp->new( type => $_ ) )
        for @operands;
    return undef if !$joined || $joined->type eq 'Unknown';

    # A MEET, not a replacement: the join is right about the operands and says
    # nothing about the operator, so it can escape upward. Bring it down to
    # what the operator can actually produce.
    my $capped = SoN::IR::Stamp::meet(
        $joined, SoN::IR::Stamp->new( type => $result ) );

    # None means the join and the cap share nothing. The cap is the honest
    # answer: what the operator yields is a fact about the OPERATOR, not about
    # what happened to arrive.
    return ( !$capped || $capped->type eq 'None' ) ? $result : $capped->type;
}

# known_ops() -> every op this table describes. For tests that assert coverage.
sub known_ops () {
    return sort keys %SIGNATURES;
}

1;
