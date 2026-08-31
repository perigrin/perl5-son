# ABOUTME: The result type of an operator is ONE fact, declared once in
# ABOUTME: B::SoN::TypeLibrary -- these are the answers it must give.
use v5.42.0;
use Test2::V0;

use B::SoN::TypeLibrary;

# WHY. The result type of an operator used to be declared TWICE: %RESULT_STAMP
# in lib/SoN/FromOptree.pm (used during the walk) and result_type/result_is_join
# in TypeLibrary (used by _stamp_derived afterwards). Nothing checked that they
# agreed, and they did not -- five entries disagreed, and one was WRONG:
#
#     Concat: TypeLibrary said join(Int,Int) capped at Str -> Int
#             but `$a . $b` is "12", a STRING, always.
#
# %RESULT_STAMP is now deleted and _result_stamp asks result_for(), so there is
# nothing left to disagree. What remains worth asserting is that the surviving
# table gives the RIGHT answers -- the ones perl gives -- for every operator the
# walker used to answer for itself. A copy that comes back has to fail here.
#
# PERL SETTLES EVERY DISAGREEMENT, and is where these came from:
#     5.7 & 3  is 1      bitwise truncates to Int whatever arrives -> not a join
#     "a" . 5  is "a5"   concat is always Str                      -> not a join
#     -5.5     is -5.5   negate preserves its operand's type       -> IS a join

# Every node type the walker's own table used to cover, with the rule it held.
# 'join' means the result varies with the operands, capped at what the op can
# yield; anything else is that type outright.
my %EXPECTED = (
    Add => 'join', Subtract => 'join', Multiply => 'join', Negate => 'join',
    Divide => 'Num', Power => 'Num', Modulo => 'Int',
    BitAnd => 'Int', BitOr => 'Int', BitXor => 'Int',
    LeftShift => 'Int', RightShift => 'Int', Complement => 'Int',
    Concat => 'Str', Length => 'Int', Count => 'Int',
    (map { $_ => 'Boolean' } qw(
        NumEq NumLt NumGt NumLe NumGe NumNe
        StrEq StrLt StrGt StrLe StrGe StrNe
    )),
    NumCmp => 'Int', StrCmp => 'Int',
    Not => 'Boolean',
);

subtest 'the one table still answers for every operator the walker needs' => sub {
    my @wrong;
    for my $op (sort keys %EXPECTED) {
        # THE ONE PUBLIC QUESTION answers both halves: a FIXED result is one
        # result_for gives with NO operands; a JOIN result is one it can only
        # give when handed some. `result_is_join` -- a boolean about the
        # caller's algorithm -- is private now, and this asks in the vocabulary
        # of answers instead.
        my $fixed = B::SoN::TypeLibrary::result_for($op);
        my $rule = defined $fixed ? $fixed
                 : defined B::SoN::TypeLibrary::result_for($op, 'Int', 'Int')
                     ? 'join'
                     : 'MISSING';
        push @wrong, "$op: expected $EXPECTED{$op} got $rule"
            unless $rule eq $EXPECTED{$op};
    }

    diag("  $_") for @wrong;
    is(\@wrong, [], 'every operator has the result rule perl gives it');
};

subtest 'result_for answers, at every arity, capped' => sub {
    my $r = \&B::SoN::TypeLibrary::result_for;

    is($r->('Add', 'Int', 'Int'), 'Int', 'Int + Int stays Int');
    is($r->('Add', 'Scalar', 'Int'), 'Num',
        'a join that escaped above the cap comes back down to it');
    is($r->('Negate', 'Int'), 'Int', 'a UNARY join fires -- Negate preserves Int');
    is($r->('Negate', 'Scalar'), 'Num', 'and is capped like any other join');
    is($r->('Concat', 'Int', 'Int'), 'Str', 'concat is Str whatever arrives');
    is($r->('NumEq', 'Str', 'Str'), 'Boolean', 'comparison is Boolean whatever arrives');
    is($r->('Add', 'Unknown', 'Int'), undef, 'an unnarrowed operand is an honest GAP');
    is($r->('Add', undef, 'Int'), undef, 'so is an absent one');
    is($r->('NoSuchOp', 'Int'), undef, 'an op the table does not describe says nothing');
};

# FromOptree must not grow a second copy of this table back.
subtest 'the walker declares no result types of its own' => sub {
    my $src = do {
        open my $fh, '<', 'lib/SoN/FromOptree.pm' or die "open FromOptree: $!";
        local $/; <$fh>;
    };
    unlike($src, qr/my \%RESULT_STAMP/,
        'no second result-type table in the walker');
    like($src, qr/B::SoN::TypeLibrary::result_for/,
        '_result_stamp asks the one table');
};

# THE THREE PERL FACTS THE RULES REST ON, asserted directly so a future edit
# that "simplifies" the set has to argue with perl rather than with a comment.
subtest 'perl agrees with the rules we chose' => sub {
    is(5.7 & 3, 1, 'bitwise truncates to an integer -- a fixed Int result');
    is("a" . 5, "a5", 'concat always yields a string -- a fixed Str result');
    is(-5.5, -5.5, 'negate preserves its operand -- a join, not a fixed Num');
};

done_testing;
