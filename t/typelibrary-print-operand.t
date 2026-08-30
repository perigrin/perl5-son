# ABOUTME: Print requires Str in every argument position -- a NODE-level contract,
# ABOUTME: recorded apart from the source-operator signatures it disagrees with.
use v5.42.0;
use Test2::V0;

use B::SoN::TypeLibrary;

# WHY THIS IS NOT AN ENTRY IN %SIGNATURES. That table mirrors chalk's, keyed by
# IR op name but describing SOURCE OPERATORS: `*` needs Num, `eq` needs Str.
# Print is a case where the node and the source builtin genuinely DISAGREE --
# the IR Print node lowers ONE representation, so every argument position is
# Str, while perl's `print` is variadic over List because perl flattens into
# it. Two claims about two different things.
#
# Chalk records its half the same way, in %_NODE_OPERAND_REPR, whose comment
# calls it an override table "for genuine node-level contracts only; an entry
# that merely restates a source signature belongs in TypeLibrary instead". This
# is the producer's mirror of that table, kept separate for the same reason:
# folding Print into %SIGNATURES would put a node-level fact in the
# source-operator table and break the mirror.
#
# WHY IT MATTERS NOW. 197 of the 238 positions where the producer inserts a
# representation coercion are Print arguments, and until this entry existed the
# producer declared no requirement for them at all -- so nothing on this side
# could answer "what does this position need?" for the largest population on
# the wire.
subtest 'Print requires Str at every position' => sub {
    is(B::SoN::TypeLibrary::operand_type('Print', $_), 'Str',
        "Print position $_ requires Str") for 0 .. 2;
};

# ONLY PRINT. The entry is a node-level override, not a licence to answer for
# ops the signatures table already covers -- those must keep coming from
# %SIGNATURES so the mirror stays honest.
subtest 'the source-operator signatures are unchanged' => sub {
    is(B::SoN::TypeLibrary::operand_type('Concat', 0), 'Str', 'Concat still Str');
    is(B::SoN::TypeLibrary::operand_type('Add',    0), 'Num', 'Add still Num');
    is(B::SoN::TypeLibrary::operand_type('Divide', 1), 'Num', 'Divide still Num');
    is(B::SoN::TypeLibrary::operand_type('StrEq',  1), 'Str', 'StrEq still Str');
};

# AND AN OP NOTHING DESCRIBES STILL ANSWERS undef, which is what lets a caller
# tell "this position requires nothing" from "requires Str". _insert_type_coercions
# skips a position whose requirement is undef; if this returned a default the
# pass would start coercing operands of every unlisted op.
subtest 'an undescribed op has no requirement' => sub {
    is(B::SoN::TypeLibrary::operand_type('Start',   0), undef, 'Start has none');
    is(B::SoN::TypeLibrary::operand_type('Nonesuch', 0), undef, 'an unknown op has none');
};

done_testing;
