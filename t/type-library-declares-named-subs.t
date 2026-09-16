# ABOUTME: an operator is a function with a weird spelling; the table is not operator-only.
# ABOUTME: a declared signature for a sub we never compile answers its callsite.
use 5.42.0;
use Test::More;
use B::SoN::TypeLibrary;
use File::Temp qw(tempdir);
use JSON::PP;
my $PERL = $^X;
my $dir = tempdir( CLEANUP => 1 );

# THE TABLE ALREADY ASKS A FUNCTION'S QUESTION. `result_for` takes a two-level
# key -- node class plus name -- and its own comment says why: "`Call/join` and
# `Call/abs` are different questions". That IS a signature lookup keyed by
# function name; the only thing making it builtin-only is which hash it reads.
subtest 'the existing key is already function-shaped' => sub {
    is B::SoN::TypeLibrary::result_for( [ 'Call', 'join' ] ), 'Str',
        'a builtin is answered by NAME, not by its node class';
    is B::SoN::TypeLibrary::result_for( [ 'Call', 'index' ] ), 'Int',
        '... and two names under one class give two answers';
};

# THE GAP. A sub we never compile has no row anywhere, so its callsite is
# Unknown -- measured on the wire:
#
#     Call Mod::f   stamp=Unknown   dispatch_kind=direct
#
# The name is known and everything else is honestly absent. That Unknown is the
# slot a DECLARATION fills: TypeScript's `@types/Foo`, sitting beside the
# `lib.d.ts` rows this table already holds for perl's own operators and
# builtins.
subtest 'a declared sub is answered like any other function' => sub {
    B::SoN::TypeLibrary::declare( 'Mod::f',
        { operands => ['Num'], result => 'Num' } );

    is B::SoN::TypeLibrary::result_for( [ 'Call', 'Mod::f' ] ), 'Num',
        'the declared result answers the callsite';
};

# A DECLARATION IS AN ASSERTION, NOT A DERIVATION, and the two must stay
# distinguishable. `*f = sub { 2 }` can replace a body at runtime, so a
# declaration can be WRONG in a way a derived signature cannot -- TypeScript
# lives with exactly this and calls it sound with respect to the declarations,
# not the program. A consumer that cannot tell them apart cannot make that
# judgement.
subtest 'a declaration is marked as one' => sub {
    ok B::SoN::TypeLibrary::is_declared('Mod::f'),
        'the declared row says it was asserted';
    ok !B::SoN::TypeLibrary::is_declared('join'),
        'while a builtin row is the language, not a claim about someone code';
};

# DECLARATIONS DO NOT OVERRIDE THE LANGUAGE. perl's own operators are facts we
# measured; letting a declaration replace one would let a bad @types row
# miscompile `join`.
subtest 'a declaration cannot overwrite a builtin' => sub {
    my $ok = eval {
        B::SoN::TypeLibrary::declare( 'join',
            { operands => ['Str'], result => 'Int' } );
        1;
    };
    ok !$ok, 'declaring over a builtin is refused';
    is B::SoN::TypeLibrary::result_for( [ 'Call', 'join' ] ), 'Str',
        'and join still yields what perl yields';
};

# AND IT REACHES A REAL CALLSITE. A call to a sub whose body this producer
# never compiled arrives Unknown. The declaration is consulted exactly there:
# AFTER the callee's graph and AFTER a record derived from its body, because a
# claim is only worth having where measurement has nothing to say.
#
# Measured, the same probe compiled twice:
#
#     without a declaration   Call Mod::g stamp=Unknown
#     with one                Call Mod::g stamp=Num
subtest 'a declaration answers a callsite the producer cannot compile' => sub {
    my $probe = "$dir/decl-callsite.pl";
    open my $fh, '>', $probe or die "open $probe: $!";
    print {$fh} "require Mod;\nmy \$x = Mod::g(3);\nprint \$x;\n";
    close $fh;

    # The declaration must exist in the process that COMPILES, so it is loaded
    # as a module -- which is how a real .d.ts-alike would arrive too.
    my $mod = "$dir/DeclFor.pm";
    open my $m, '>', $mod or die "open $mod: $!";
    print {$m} <<'DECL';
package DeclFor;
use B::SoN::TypeLibrary;
BEGIN { B::SoN::TypeLibrary::declare('Mod::g',
        { operands => ['Num'], result => 'Num' }) }
1;
DECL
    close $m;

    my $stamp_of = sub ($extra) {
        my $json = qx{$PERL -Ilib $extra -MO=SoN,json,not_package=SoN $probe 2>/dev/null};
        my $wire = eval { JSON::PP->new->decode($json) } or return 'NO-GRAPH';
        my ($c) = grep { ( $_->{fields}{name} // '' ) eq 'Mod::g' }
                  ( ( $wire->{methods}{'main::__PROGRAM__'}{nodes} // [] )->@* );
        return $c ? ( $c->{stamp} // 'NONE' ) : 'NO-CALL';
    };

    is $stamp_of->(''), 'Unknown',
        'without a declaration the callsite is honestly Unknown';
    is $stamp_of->("-I$dir -MDeclFor"), 'Num',
        'and the declaration is what fills it';
};

done_testing;
