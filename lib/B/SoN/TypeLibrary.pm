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
# its input. `result_for` owns that decision; it is not a caller's to make.

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
    And Or DefinedOr
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

    # SHORT-CIRCUITS RETURN AN OPERAND, NOT A BOOLEAN. `0 || "hello"` is
    # "hello", `"x" && 7` is 7, `undef // 5` is 5 -- so the result is the join
    # of the two arms, the same shape as Add.
    #
    # `operands` is EMPTY on purpose: these impose no requirement on their arms
    # (any value has a truth interpretation), and a requirement here would make
    # the coercion pass insert a Coerce on every `||` in the corpus.
    #
    # The bound is `List`, the widest thing a scalar-or-list arm can be, which
    # meets transparently: meet(Int,List) is Int, meet(ArrayRef,List) is
    # ArrayRef. An operator that hands back its operand unchanged must not
    # narrow it, and a tighter bound here would do exactly that.
    And        => { operands => [], result => 'List' },
    Or         => { operands => [], result => 'List' },
    DefinedOr  => { operands => [], result => 'List' },
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

    # `xor` is the LOW-PRECEDENCE BOOLEAN operator, not a bitwise one: `5 xor 3`
    # is false (both operands are true), where `5 ^ 3` is 6. It imposes nothing
    # on its operands -- anything has a truth value -- and always yields a
    # Boolean. BitXor is the separate node for `^`.
    Xor        => { operands => [], result => 'Boolean' },

    # Smartmatch yields a Boolean whatever the operand kinds. The MATCHING
    # rules are elaborate and perl deprecated them, but the result type is not
    # in question, and leaving it undeclared was the only thing keeping this
    # node on the not-yet-declared list.
    Match      => { operands => [], result => 'Boolean' },
    IsaOp      => { operands => ['Scalar', 'Str'], result => 'Boolean' },

    # Range yields a list of integers.
    Range      => { operands => ['Int', 'Int'], result => 'List' },
);

# THE SECOND INDEX, KEYED BY BUILTIN NAME.
#
# ~180 optree ops collapse to ONE generic `Call` node, so %SIGNATURES -- keyed
# by IR NODE NAME -- can only give one answer for all of them, and that answer
# was Unknown for every one. The key that separates them already rides on the
# node: a builtin Call carries `dispatch_kind => 'builtin'` and `name => 'join'`.
# This is the index that reads it. Same vocabulary as %SIGNATURES (operands /
# result), and the same join rule via %BUILTIN_RESULT_IS_JOIN below.
#
# PRIVATE. There is exactly ONE public question -- `result_for` -- and it routes
# a builtin Call here itself. A caller must never have to know which of the two
# tables holds its answer.
#
# EVERY ROW WAS RUN THROUGH PERL. What is NOT here matters as much as what is;
# the omissions and their reasons are recorded below the table.
#
# ONLY THE `result` HALF IS WIRED. `operand_type` is asked with a node name by
# both of its callers, and both INSERT COERCIONS from the answer -- so routing
# builtins into it would not type a builtin, it would rewrite graphs. The
# operands are stated anyway because a signature with a result and no operands
# is half a fact, and the coercion question is a separate change with its own
# fingerprint to answer for.
my %BUILTIN_SIGNATURES = (
    # `join` is Str however its separator and list are typed, and `join(",")`
    # over an empty list is "" -- still Str, never undef.
    join   => { operands => ['Str'], result => 'Str' },

    # A position or a count. Both index and rindex return -1 on a miss, which
    # is an Int like any hit.
    index  => { operands => ['Str', 'Str'], result => 'Int' },
    rindex => { operands => ['Str', 'Str'], result => 'Int' },

    # `tell` yields a byte offset, and -1 on failure -- Int either way.
    tell   => { operands => [], result => 'Int' },

    # THE FILESYSTEM FOUR, and they are NOT uniform -- one row cannot cover
    # them, the same way it cannot cover the file tests. Measured on 5.42.0:
    #
    #     close   ok=1  fail=""      defined, length 0
    #     rmdir   ok=1  fail=0       defined, numeric 0
    #     unlink  two=2 none=0       a COUNT of files removed
    #     binmode ok=1  fail=undef   UNDEF on failure
    #
    # `close` is the one this table's own note deferred -- "typed once someone
    # measures pp_close the way pp_open was measured, rather than assuming a
    # Boolean". Measured, it IS perl's canonical true/false pair, so the
    # assumption was right and now carries evidence.
    close  => { operands => [], result => 'Boolean' },
    rmdir  => { operands => ['Str'], result => 'Boolean' },

    # A COUNT, not a boolean that happens to be true: `unlink @files` yields 2
    # for two files removed, and typing it Boolean would discard that.
    unlink => { operands => ['Str'], result => 'Int' },

    # UNDEF ON FAILURE, so the honest answer is the JOIN and the lattice states
    # it -- join(Boolean, Undef) = Scalar, the same derivation `open` uses.
    # Boolean descends from Str here, so it is the wrong answer on its own.
    binmode => { operands => [], result => 'Scalar' },

    # tr/// COUNTS what it changed; tr///r RETURNS THE NEW STRING. perl gives
    # them separate op names (verified with B::Concise: `trans` vs `transr`),
    # so unlike `subst` -- where /r shares the `subst` op name and is only
    # distinguishable by PMf_NONDESTRUCT -- these are two honest fixed rows.
    trans  => { operands => ['Str'], result => 'Int' },
    transr => { operands => ['Str'], result => 'Str' },

    # `abs` is a JOIN, not a fixed row: abs(-5) is 5 (IOK) and abs(-5.5) is
    # 5.5 (NOK). Its result is its operand's type, capped at Num -- exactly
    # `Negate`'s shape. A fixed Num row here would WIDEN abs(-5) from Int,
    # which is the regression this table exists to avoid.
    abs    => { operands => ['Num'], result => 'Num' },

    # `open` returns PUSHi((I32)PL_forkprocess) on success -- an INTEGER, the
    # child pid for a pipe-open and 1 otherwise -- and RETPUSHUNDEF on failure
    # (pp_sys.c, PP_wrapped(pp_open)). is_bool() is false on BOTH paths, so it
    # is not a Boolean however boolean its use reads. join(Int, Undef) is what
    # the LATTICE gives for that pair, and the lattice is what decides it.
    open   => { operands => [], result => 'Scalar' },

    # A line, or undef at EOF, or the whole file in list context. A
    # context-sensitive op is still table-eligible at the JOIN of its results:
    # sound, and vaguer than reading OPf_WANT at the construction site would
    # be, but never wrong. Scalar <: List, so that join is List.
    readline => { operands => [], result => 'List' },

    # THE FILE TESTS THAT CAN MISS. All four behave identically, measured on
    # all THREE paths -- the third is the one an earlier row missed:
    #
    #     -c /dev/null      1      is_bool   (true)
    #     -c /etc/hostname  ""     is_bool   (false)
    #     -c missing        undef  NOT a bool
    #
    # `ftchr` was typed Boolean on the strength of is_bool over the first two.
    # Boolean does not admit undef in this lattice, so that was WRONG rather
    # than narrow -- the same rule this table applies to every other
    # undef-on-failure op. The honest answer is join(Boolean,Undef) = Scalar.
    #
    # Their siblings are still NOT typed with them: -s is an Int byte count,
    # -M a Num of days. The family gets no blanket row; each member earns its
    # own or none.
    ftchr  => { operands => [], result => 'Scalar' },
    ftdir  => { operands => [], result => 'Scalar' },
    ftfile => { operands => [], result => 'Scalar' },
    ftlink => { operands => [], result => 'Scalar' },

    # chdir IS a true Boolean, and the distinction from the file tests above is
    # measured rather than assumed: is_bool on BOTH paths, 1 and "", never
    # undef. They look alike and are not.
    chdir  => { operands => ['Str'], result => 'Boolean' },

    # FIXED STRING RESULTS, no failure mode. substr slices, quotemeta escapes,
    # pack builds -- each a Str however its operands are typed.
    substr    => { operands => ['Str'], result => 'Str' },
    quotemeta => { operands => ['Str'], result => 'Str' },
    pack      => { operands => ['Str'], result => 'Str' },

    # `int` TRUNCATES TOWARD ZERO: int(3.7) is 3 and int(-3.7) is -3. An Int
    # either way, never the Num it was handed.
    int    => { operands => ['Num'], result => 'Int' },

    # shift/pop REMOVE AND RETURN ONE element, so the result is a scalar
    # whatever the array holds -- and in ANY context, unlike `splice`. This row
    # absorbs _floor_element_removals in B/SoN.pm, which said the same thing in
    # a later pass. It is a FLOOR: FromOptree stamps the array's own element
    # type when it can read it (`my @q=(1,2,3); shift @q` is Int), and that
    # narrower answer must keep precedence over this one.
    shift  => { operands => [], result => 'Scalar' },
    pop    => { operands => [], result => 'Scalar' },
);

# The builtins whose result VARIES with their operands, capped by `result` --
# the builtin-name counterpart of %RESULT_IS_JOIN.
my %BUILTIN_RESULT_IS_JOIN = map { $_ => 1 } qw(
    abs
);

# WHAT IS DELIBERATELY ABSENT, and why. An honest Unknown beats a guess; 89b0008
# reverted a guessed Scalar for exactly this reason. Every one of these appears
# as a reachable untyped builtin Call over perl's t/base, t/cmd, t/comp and
# t/opbasic, so each is a row someone will be tempted to add.
#
#   CONTEXT-SENSITIVE -- one op name, two types. A row here is still allowed
#   at the JOIN of the two results, which is sound but vaguer than reading
#   `$op->flags` at the construction site; `readline` takes that trade (List),
#   these do not, because the join reaches all the way to Unknown and says
#   nothing:
#     keys      scalar context is a count, list context is the keys
#     caller    scalar context is the package, list context is 3+ values
#
#   ONE OP NAME, TWO RESULTS, distinguishable only by a flag on the op:
#     subst     s///g returns a COUNT (Int); s///gr returns the STRING (Str).
#               Both are op name `subst`; only PMf_NONDESTRUCT separates them.
#
#   RETURNS undef ON FAILURE. `Boolean` descends from Str here, not from Undef,
#   so Boolean is a WRONG answer for these -- but that rules out one candidate,
#   NOT a row: ask the lattice for join(success, Undef) and take what it says.
#   `open` does exactly that above and lands on Scalar, and `binmode` follows
#   the same derivation. What remains absent is only what stays genuinely
#   unresolved:
#     eof               typed once someone measures pp_eof the way pp_open was
#                       measured, rather than assuming a Boolean. (`close` WAS
#                       measured -- 1 and "" -- and is typed Boolean above.)
#     the file tests    not uniform among themselves: -c is a true Boolean
#                       (typed above), -s a byte COUNT (Int), -M fractional
#                       days (Num). No single row covers the family; each
#                       member is measured on its own or left alone.
#
#   THE VALUE IS THE PROGRAM'S, NOT THE OPERATOR'S:
#     require, dofile   a module returns 1, but a do-FILE returns the file's
#                       last expression -- anything at all
#     tie               returns the tied object
#     mapstart, grepstart   a list whose size depends on the block
#     prototype         a Str, or undef when there is no prototype
#
#   NOTHING TO GAIN: `prtf` returns 1, but every reachable occurrence is in
#   void context, so the value is discarded. A row would be correct and idle.

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
    # A BUILTIN CALL IS KEYED BY ITS NAME, exactly as `result_for` keys it. One
    # `Call` node stands for ~180 builtins, so asking what `Call` requires has
    # ~180 answers; asking what `abs` requires has one.
    if ( ref $ir_op eq 'ARRAY' ) {
        my (undef, $builtin) = $ir_op->@*;
        my $sig = defined $builtin ? $BUILTIN_SIGNATURES{$builtin} : undef;
        return ( ( $sig // return undef )->{operands} // [] )->[$position];
    }

    # The node-level contract wins where it exists: it is a fact about the node
    # this position belongs to, not about the operator it was spelled with.
    return $NODE_OPERAND_TYPE{$ir_op} if exists $NODE_OPERAND_TYPE{$ir_op};
    my $sig = $SIGNATURES{$ir_op} or return undef;
    return ( $sig->{operands} // [] )->[$position];
}

# type_key($node) -> the key `operand_type` and `result_for` want for this node.
#
# A builtin Call answers to ['Call', $name]; everything else to its bare
# operation. Callers holding a node should ask HERE rather than reconstruct the
# shape, so the two questions cannot drift apart on how a builtin is addressed.
sub type_key ($node) {
    my $op = $node->operation;
    return $op unless $op eq 'Call' && $node->can('dispatch_kind');
    return $op unless ( $node->dispatch_kind // '' ) eq 'builtin';
    my $name = $node->can('name') ? $node->name : undef;
    return defined $name ? [ $op, $name ] : $op;
}

# _result_type($ir_op) -> what this op yields, or undef when the op is unknown.
#
# Whether that is the answer OUTRIGHT or a CEILING to meet the operand join
# against is `_result_is_join`'s question, not this one's.
#
# PRIVATE. Both halves are inputs to `result_for`'s rule, not answers on their
# own -- see result_for's header for why a caller holding the raw pair
# reimplements join-then-cap and gets to make its own mistakes about arity.
sub _result_type ($ir_op) {
    my $sig = $SIGNATURES{$ir_op} or return undef;
    return $sig->{result};
}

# _result_is_join($ir_op) -> does this op's result VARY with its operands?
#
# True for `$a + $b` (Int when both are Int, Num otherwise); false for `$a == $b`
# (Boolean whatever arrives). A true answer means join the operands and MEET
# that against _result_type; a false one means take _result_type outright.
sub _result_is_join ($ir_op) {
    return $RESULT_IS_JOIN{$ir_op} ? 1 : 0;
}

# result_for($ir_op, @operand_types) -> the type this op yields given those
# operands, or undef when the table cannot say.
#
# $ir_op is an IR OP NAME ('Add', 'Concat'), or -- for a builtin Call, whose
# node name says nothing because ~180 ops share it -- the pair
# ['Call', $builtin_name]. THE ONE PUBLIC QUESTION: which of the two indices
# holds the answer is this function's business, never a caller's.
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
    # A BUILTIN CALL IS KEYED BY ITS NAME, not by the node it shares with ~180
    # others. `Call/join` and `Call/abs` are different questions; routing them
    # here rather than at the call site is what keeps ONE public question.
    my ($result, $is_join);
    if ( ref $ir_op eq 'ARRAY' ) {
        my (undef, $builtin) = $ir_op->@*;
        my $sig = defined $builtin ? $BUILTIN_SIGNATURES{$builtin} : undef;
        $result  = ( $sig // return undef )->{result};
        $is_join = $BUILTIN_RESULT_IS_JOIN{$builtin} ? 1 : 0;
    }
    else {
        $result  = _result_type($ir_op) // return undef;
        $is_join = _result_is_join($ir_op);
    }
    return $result unless $is_join;

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

# known_builtins() -> every BUILTIN this table describes. The builtin index's
# counterpart of known_ops, and the only window onto it: the rows themselves
# stay private, and a caller still asks `result_for` for any actual answer.
sub known_builtins () {
    return sort keys %BUILTIN_SIGNATURES;
}

1;
