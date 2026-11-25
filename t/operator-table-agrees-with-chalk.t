# ABOUTME: B::SoN's operator table (B::SoN::TypeLibrary) and chalk's (TypeLibrary's binary and
# ABOUTME: unary signatures) give every operator the same operand and result types.
use v5.42.0;
use Test2::V0;

use B::SoN::TypeLibrary;

# WHY. Each repo declares the operators' types, B::SoN by IR node, chalk by
# source spelling. Until both read one table
# (docs/plans/2026-11-25-one-lattice-one-table.md) this keeps them the same:
# an operator either side adds or changes fails here until the other agrees.
# chalk's t/bootstrap/operator-table-agrees-with-b-son.t is the same check,
# and holds the same maps and lists, from the other side.
my $chalk = $ENV{SON_CHALK} // "$ENV{HOME}/dev/chalk";
skip_all "chalk not found at $chalk (set SON_CHALK)"
    unless -f "$chalk/lib/Chalk/Grammar/Perl/TypeLibrary.pm";
push @INC, "$chalk/lib";    # after ours: only Chalk:: modules come from there
require Chalk::Grammar::Perl::TypeLibrary;
my $C = 'Chalk::Grammar::Perl::TypeLibrary';

# chalk's source operator -> B::SoN's IR node (the wire's name for it).
my %BINARY = (
    '+' => 'Add', '-' => 'Subtract', '*' => 'Multiply', '/' => 'Divide',
    '%' => 'Modulo', '**' => 'Power', '.' => 'Concat', 'x' => 'Repeat',
    '==' => 'NumEq', '!=' => 'NumNe', '<' => 'NumLt', '>' => 'NumGt',
    '<=' => 'NumLe', '>=' => 'NumGe', '<=>' => 'NumCmp',
    'eq' => 'StrEq', 'ne' => 'StrNe', 'lt' => 'StrLt', 'gt' => 'StrGt',
    'le' => 'StrLe', 'ge' => 'StrGe', 'cmp' => 'StrCmp',
    '&&' => 'And', 'and' => 'And', '||' => 'Or', 'or' => 'Or',
    '//' => 'DefinedOr', 'xor' => 'Xor',
    '&' => 'BitAnd', '|' => 'BitOr', '^' => 'BitXor',
    '<<' => 'LeftShift', '>>' => 'RightShift',
    'isa' => 'IsaOp', '=~' => 'RegexMatch', '!~' => 'NotMatch',
    '..' => 'Range', '...' => 'Range', '=' => 'Assign',
);
my %UNARY = (
    '-' => 'Negate', '+' => 'UnaryPlus', '!' => 'Not', 'not' => 'Not',
    '~' => 'Complement', '\\' => 'Ref',
);
# B::SoN's node -> chalk's builtin row, for the operators chalk spells as a
# named function.
my %BUILTIN = (
    Length => 'length', Defined => 'defined', Exists => 'exists',
    Delete => 'delete', RefType => 'ref', Wantarray => 'wantarray',
);
# Rows only one side has: none of these is an operator of the other table.
my %ONLY_B_SON = map { $_ => 1 } qw(
    Count Increment Match SubDefined Slice MakeCell CellParam CellRead CellWrite
);
my %ONLY_CHALK = map { $_ => 1 } qw( Assign Ref );

# Disagreements held by name, each with why it is not settled. One that no
# longer occurs fails too: take it out.
my %HELD = (
    # THE RIGHT OPERAND. B::SoN's node keeps a constant pattern as an
    # attribute, its one input the subject; chalk's row types the source's
    # right operand as Regex, which is narrower than perl ("abc" =~ "b"
    # compiles the string and matches). Settling it is agreeing what the
    # node's operand 1 is.
    'RegexMatch (binary =~)' => 'right operand: an attribute vs Regex',
    'NotMatch (binary !~)'   => 'right operand: an attribute vs Regex',
    # THE OPERAND. chalk's row types the source's one EXPR (Scalar); B::SoN's
    # node requires nothing, because a requirement there inserts coercions,
    # and Exists/Delete take a container and a key, not one scalar.
    'Defined (builtin defined)' => 'Scalar operand vs no requirement',
    'Exists (builtin exists)'   => 'Scalar operand vs container and key',
    'Delete (builtin delete)'   => 'Scalar operand vs container and key',
    'RefType (builtin ref)'     => 'Scalar operand vs no requirement',
);

# A row as [operands..., '->', result]. A `List` operand, or none, requires
# nothing; trailing ones are dropped. A chalk builtin's trailing List is variadic.
sub row (@t) {
    my $result = pop @t;
    @t = map { !defined || $_ eq 'List' ? '' : $_ } @t;
    pop @t while @t && $t[-1] eq '';
    return join( ' ', map( $_ eq '' ? '-' : $_, @t ), '->', $result // '-' );
}
sub chalk_row ($kind, $name) {
    if ( $kind eq 'binary' ) {
        my $s = $C->can('get_binary_op')->($name);
        return row( $s->{left}, $s->{right}, $s->{result} );
    }
    if ( $kind eq 'unary' ) {
        my $s = $C->can('get_unary_op')->($name);
        return row( $s->{operand}, $s->{result} );
    }
    my $s = $C->can('get_builtin')->($name) // return undef;
    return row( $s->{arg_types}->@*, $s->{return_type} );
}
sub son_row ($op) {
    my $s = B::SoN::TypeLibrary::signature($op) // return undef;
    return row( $s->{operands}->@*, $s->{result} );
}

my ( @unmapped, %diff );
my %pairs;    # "IR (kind name)" -> [chalk row, B::SoN row]
for my $kind (qw(binary unary)) {
    my $map = $kind eq 'binary' ? \%BINARY : \%UNARY;
    for my $name ( $C->can("${kind}_ops")->() ) {
        my $ir = $map->{$name} // do { push @unmapped, "chalk $kind `$name`"; next };
        next if $ONLY_CHALK{$ir};
        $pairs{"$ir ($kind $name)"} = [ chalk_row( $kind, $name ), son_row($ir) ];
    }
}
my %from_chalk = map { $_ => 1 } values %BINARY, values %UNARY;
for my $ir ( B::SoN::TypeLibrary::known_ops() ) {
    if ( my $b = $BUILTIN{$ir} ) {
        $pairs{"$ir (builtin $b)"} = [ chalk_row( builtin => $b ), son_row($ir) ];
    }
    elsif ( !$from_chalk{$ir} && !$ONLY_B_SON{$ir} ) {
        push @unmapped, "B::SoN `$ir`";
    }
}
is( \@unmapped, [], 'every operator either table declares is mapped to the other' );

is( [ grep { defined son_row($_) } sort keys %ONLY_CHALK ], [],
    'the chalk-only operators have no B::SoN row' );
is( [ grep { !defined son_row($_) } sort keys %ONLY_B_SON ], [],
    'the B::SoN-only operators have a B::SoN row' );

for my $k ( sort keys %pairs ) {
    my ( $c, $s ) = $pairs{$k}->@*;
    $_ //= 'NO ROW' for $c, $s;
    $diff{$k} = "chalk $c, B::SoN $s" if $c ne $s;
}
diag "  $_: $diff{$_}" . ( $HELD{$_} ? ' (held)' : '' ) for sort keys %diff;
is( [ sort keys %diff ], [ sort keys %HELD ],
    'operand and result types agree, but the disagreements held by name' );

done_testing;
