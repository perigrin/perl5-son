# ABOUTME: B::SoN::TypeLibrary -- what each IR op requires of its operands and yields.
# ABOUTME: Pins the three facts and the fixed-vs-ceiling distinction.
use 5.42.0;
use utf8;
use Test::More;
use B::SoN::TypeLibrary;

subtest 'an operator publishes what it requires of its operands' => sub {
    is B::SoN::TypeLibrary::operand_type( 'Multiply', 0 ), 'Num',
        '`*` requires Num of its left operand';
    is B::SoN::TypeLibrary::operand_type( 'Multiply', 1 ), 'Num',
        'and of its right';
    is B::SoN::TypeLibrary::operand_type( 'Concat', 0 ), 'Str',
        '`.` requires Str';
    is B::SoN::TypeLibrary::operand_type( 'BitAnd', 0 ), 'Int',
        '`&` requires Int';
    is B::SoN::TypeLibrary::operand_type( 'Repeat', 1 ), 'Int',
        '`x` requires Str on the left and Int on the right';
};

subtest 'an unconstrained operand is distinct from an unknown op' => sub {
    is B::SoN::TypeLibrary::operand_type( 'Not', 0 ), undef,
        '`!` imposes nothing on its operand';
    is B::SoN::TypeLibrary::result_type('Not'), 'Boolean',
        'but its RESULT is still known';
    is B::SoN::TypeLibrary::result_type('NoSuchOp'), undef,
        'while an op absent from the table is undef throughout';
};

subtest 'a result is either FIXED or a CEILING' => sub {
    # Fixed: the same whatever arrives.
    ok !B::SoN::TypeLibrary::result_is_join('NumEq'),
        '`==` yields Boolean regardless of its operands';
    is B::SoN::TypeLibrary::result_type('NumEq'), 'Boolean', 'namely Boolean';

    # Ceiling: varies with the operands, but bounded.
    ok B::SoN::TypeLibrary::result_is_join('Multiply'),
        '`*` varies with its operands';
    is B::SoN::TypeLibrary::result_type('Multiply'), 'Num',
        'but is never wider than Num';
};

subtest 'Divide varies but is NOT a join of its operands' => sub {
    # 4/2 is Int, 1/2 is not -- so its result cannot be read off the operands,
    # yet it is still capped.
    ok !B::SoN::TypeLibrary::result_is_join('Divide'),
        'the result is not the operand join';
    is B::SoN::TypeLibrary::result_type('Divide'), 'Num',
        'and it is capped at Num';
};

subtest 'the comparison families are separated correctly' => sub {
    # Numeric and string comparisons differ in what they REQUIRE, not in what
    # they yield -- a table keyed only on the result would conflate them.
    is B::SoN::TypeLibrary::operand_type( 'NumEq', 0 ), 'Num', '== takes Num';
    is B::SoN::TypeLibrary::operand_type( 'StrEq', 0 ), 'Str', 'eq takes Str';
    is B::SoN::TypeLibrary::result_type('NumEq'), 'Boolean', 'both yield Boolean';
    is B::SoN::TypeLibrary::result_type('StrEq'), 'Boolean', '...';

    # And the three-way comparisons yield a number, not a boolean.
    is B::SoN::TypeLibrary::result_type('NumCmp'), 'Int', '<=> yields -1/0/1';
    is B::SoN::TypeLibrary::result_type('StrCmp'), 'Int', 'and so does cmp';
};

subtest 'every op with operands also declares a result' => sub {
    # A half-filled entry would let a caller narrow an operand and then have
    # nothing to say about the value produced from it.
    my @missing;
    for my $op ( B::SoN::TypeLibrary::known_ops() ) {
        push @missing, $op unless defined B::SoN::TypeLibrary::result_type($op);
    }
    is_deeply \@missing, [], 'no entry declares operands without a result'
        or diag "missing result: @missing";
};

done_testing;
