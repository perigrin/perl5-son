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
    is B::SoN::TypeLibrary::result_for('Not'), 'Boolean',
        'but its RESULT is still known';
    is B::SoN::TypeLibrary::result_for('NoSuchOp'), undef,
        'while an op absent from the table is undef throughout';
};

# ASKED IN THE VOCABULARY OF ANSWERS. `result_is_join` was a boolean about the
# CALLER'S algorithm and is now private; the same distinction is visible through
# the one public question, because a FIXED result is one result_for can give
# with NO operands and a JOIN result is one it cannot.
subtest 'a result is either FIXED or a CEILING' => sub {
    # Fixed: the same whatever arrives.
    is B::SoN::TypeLibrary::result_for('NumEq'), 'Boolean',
        '`==` yields Boolean regardless of its operands';

    # Ceiling: varies with the operands, but bounded.
    is B::SoN::TypeLibrary::result_for('Multiply'), undef,
        '`*` cannot be answered without its operands';
    is B::SoN::TypeLibrary::result_for( 'Multiply', 'Int', 'Int' ), 'Int',
        'it varies with them';
    is B::SoN::TypeLibrary::result_for( 'Multiply', 'Scalar', 'Scalar' ), 'Num',
        'but is never wider than Num';
};

subtest 'Divide varies but is NOT a join of its operands' => sub {
    # 4/2 is Int, 1/2 is not -- so its result cannot be read off the operands,
    # yet it is still capped.
    is B::SoN::TypeLibrary::result_for( 'Divide', 'Int', 'Int' ), 'Num',
        'the result is not the operand join -- Int/Int is still Num';
    is B::SoN::TypeLibrary::result_for('Divide'), 'Num',
        'and it is capped at Num whatever arrives';
};

subtest 'the comparison families are separated correctly' => sub {
    # Numeric and string comparisons differ in what they REQUIRE, not in what
    # they yield -- a table keyed only on the result would conflate them.
    is B::SoN::TypeLibrary::operand_type( 'NumEq', 0 ), 'Num', '== takes Num';
    is B::SoN::TypeLibrary::operand_type( 'StrEq', 0 ), 'Str', 'eq takes Str';
    is B::SoN::TypeLibrary::result_for('NumEq'), 'Boolean', 'both yield Boolean';
    is B::SoN::TypeLibrary::result_for('StrEq'), 'Boolean', '...';

    # And the three-way comparisons yield a number, not a boolean.
    is B::SoN::TypeLibrary::result_for('NumCmp'), 'Int', '<=> yields -1/0/1';
    is B::SoN::TypeLibrary::result_for('StrCmp'), 'Int', 'and so does cmp';
};

subtest 'every op with operands also declares a result' => sub {
    # A half-filled entry would let a caller narrow an operand and then have
    # nothing to say about the value produced from it.
    # A join op declines with no operands, so ask it with some: whatever the
    # arity, an op with a result answers ONE of the two.
    my @missing;
    for my $op ( B::SoN::TypeLibrary::known_ops() ) {
        next if defined B::SoN::TypeLibrary::result_for($op);
        next if defined B::SoN::TypeLibrary::result_for( $op, 'Int', 'Int' );
        push @missing, $op;
    }
    is_deeply \@missing, [], 'no entry declares operands without a result'
        or diag "missing result: @missing";
};

# THE BUILTIN INDEX GETS THE SAME GATE. Its rows are private, but a row with
# operands and no result would be as half-filled here as in the node table.
subtest 'every builtin declares a result' => sub {
    my @missing;
    for my $b ( B::SoN::TypeLibrary::known_builtins() ) {
        my $key = [ 'Call', $b ];
        next if defined B::SoN::TypeLibrary::result_for($key);
        next if defined B::SoN::TypeLibrary::result_for( $key, 'Int' );
        push @missing, $b;
    }
    is_deeply \@missing, [], 'no builtin row declares operands without a result'
        or diag "missing result: @missing";
};

done_testing;
