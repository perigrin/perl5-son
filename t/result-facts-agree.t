# ABOUTME: The result type of an operator is one fact -- FromOptree's
# ABOUTME: %RESULT_STAMP and TypeLibrary must never disagree about it.
use v5.42.0;
use Test2::V0;

use B::SoN::TypeLibrary;

# WHY. The result type of an operator is declared TWICE: %RESULT_STAMP in
# lib/SoN/FromOptree.pm (used during the walk) and result_type/result_is_join
# in TypeLibrary (used by _stamp_derived afterwards). Nothing checked that they
# agreed, and they did not -- five entries disagreed, and one was WRONG:
#
#     Concat: TypeLibrary said join(Int,Int) capped at Str -> Int
#             but `$a . $b` is "12", a STRING, always.
#
# It was masked, not harmless: %RESULT_STAMP stamps Concat during the walk and
# _stamp_derived only fills Unknowns, so the wrong entry never got the chance
# to answer. Delete the walker's table and the bug ships.
#
# TypeLibrary's own header records this pattern from before: "Three partial
# copies of one table, none of them labelled as such." Adding `Count` (93a2d12)
# missed one copy and shipped an Unknown. This test is the guard until the
# copies are merged -- see
# docs/plans/2026-08-31-one-operator-one-declaration.md.
#
# PERL SETTLES EVERY DISAGREEMENT, and is where the fixes came from:
#     5.7 & 3  is 1      bitwise truncates to Int whatever arrives -> not a join
#     "a" . 5  is "a5"   concat is always Str                      -> not a join
#     -5.5     is -5.5   negate preserves its operand's type       -> IS a join

# %RESULT_STAMP is lexical to FromOptree, so read it from the source. Scraping
# is fragile -- if this ever stops finding entries the count assertion below
# fails rather than silently passing on an empty set.
sub result_stamp_table () {
    my $src = do {
        open my $fh, '<', 'lib/SoN/FromOptree.pm' or die "open FromOptree: $!";
        local $/; <$fh>;
    };
    my ($body) = $src =~ /my \%RESULT_STAMP = \((.*?)\n    \);/s
        or die 'could not find %RESULT_STAMP in lib/SoN/FromOptree.pm';

    my %t;
    # Plain `Name => 'Value',` entries.
    while ($body =~ /^\s+(\w+)\s+=> '(\w+)',/gm) { $t{$1} = $2 }
    # The `(map { $_ => 'Boolean' } qw(...))` block.
    while ($body =~ /map \{ \$_ => '(\w+)' \} qw\(\s*(.*?)\s*\)/gs) {
        my ($val, $names) = ($1, $2);
        $t{$_} = $val for split ' ', $names;
    }
    return %t;
}

subtest 'the scrape actually found the table' => sub {
    my %t = result_stamp_table();
    cmp_ok(scalar keys %t, '>=', 25,
        'found the expected number of %RESULT_STAMP entries')
        or diag('the scrape broke -- every assertion below would pass vacuously');
};

subtest 'both tables give the same result rule for every shared operator' => sub {
    my %t = result_stamp_table();
    my @disagree;

    for my $op (sort keys %t) {
        my $tl_result = B::SoN::TypeLibrary::result_type($op);
        next unless defined $tl_result;   # TypeLibrary need not know every node

        my $tl_rule = B::SoN::TypeLibrary::result_is_join($op)
            ? 'join' : $tl_result;

        push @disagree, "$op: RESULT_STAMP=$t{$op} TypeLibrary=$tl_rule"
            unless $tl_rule eq $t{$op};
    }

    diag("  $_") for @disagree;
    is(\@disagree, [], 'no operator has two different result rules');
};

# THE THREE PERL FACTS THE FIX RESTS ON, asserted directly so a future edit
# that "simplifies" the set has to argue with perl rather than with a comment.
subtest 'perl agrees with the rules we chose' => sub {
    is(5.7 & 3, 1, 'bitwise truncates to an integer -- a fixed Int result');
    is("a" . 5, "a5", 'concat always yields a string -- a fixed Str result');
    is(-5.5, -5.5, 'negate preserves its operand -- a join, not a fixed Num');
};

done_testing;
