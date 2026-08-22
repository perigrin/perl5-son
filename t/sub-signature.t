# ABOUTME: The producer records a sub's DECLARED signature from argcheck/argelem.
# ABOUTME: Signature-less, empty-signature, and slurpy are three distinct answers.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub wire_for ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    return JSON::PP->new->decode($json);
}

sub sig_for ( $src, $name, $sub ) {
    my $wire = wire_for( $src, $name );
    return ( ( $wire->{classes}{main} // {} )->{subs} // {} )->{$sub};
}

# The optree carries the whole signature; the producer has been discarding it
# one op above where it looks. Measured with B::Concise:
#
#   sub ary(@x)      argcheck(0,0,@)  argelem(0)[@x] v/AV
#   sub two($a,$b)   argcheck(2,0)    argelem(0)[$a] + argelem(1)[$b]
#   sub empty()      argcheck(0,0)    (no argelem)
#   sub none         (NO argcheck at all)
#
# argcheck's THIRD operand is the slurpy sigil and is load-bearing: reading only
# the first two operands reports `sub ary(@x)` as taking no arguments, which
# inverts it.

subtest 'a declared signature is recorded positionally with sigils' => sub {
    my $rec = sig_for( 'sub two($a,$b) { $a + $b } print two(1,2), "\n";',
        'two', 'two' );
    ok $rec, 'sub two recorded' or return;

    is $rec->{signature}{kind}, 'declared', 'kind is declared';
    is $rec->{signature}{mandatory}, 2, 'two mandatory params';
    is $rec->{signature}{optional},  0, 'no optional params';
    ok !$rec->{signature}{slurpy}, 'not slurpy';

    my $p = $rec->{signature}{params};
    is scalar @$p, 2, 'two parameter records' or return;
    is $p->[0]{index}, 0,     'first is index 0';
    is $p->[0]{name},  '$a',  'first is $a';
    is $p->[0]{sigil}, '$',   'first is a scalar';
    is $p->[1]{index}, 1,     'second is index 1';
    is $p->[1]{name},  '$b',  'second is $b';
};

# THE THIRD OPERAND. `sub ary(@x)` is argcheck(0,0,@): zero mandatory, zero
# optional, slurpy array. A reader that ignores operand 3 calls this arity zero
# -- the exact inversion this asserts against.
subtest 'a slurpy array is recorded as slurpy, not as arity zero' => sub {
    my $rec = sig_for( 'sub ary(@x) { scalar @x } print ary(1,2), "\n";',
        'ary', 'ary' );
    ok $rec, 'recorded' or return;
    is $rec->{signature}{kind}, 'declared', 'declared';
    is $rec->{signature}{slurpy}, '@', 'slurpy sigil is @';
    is $rec->{signature}{mandatory}, 0, 'zero mandatory';
    my $p = $rec->{signature}{params};
    is scalar @$p, 1, 'one parameter record' or return;
    is $p->[0]{sigil}, '@', 'typed by its sigil, an array';
};

# A slurpy is NOT always an array (perigrin). %h is a hash.
subtest 'a slurpy hash is recorded as a hash' => sub {
    my $rec = sig_for( 'sub hsh(%h) { scalar keys %h } print hsh(a=>1), "\n";',
        'hsh', 'hsh' );
    ok $rec, 'recorded' or return;
    is $rec->{signature}{slurpy}, '%', 'slurpy sigil is %';
    is $rec->{signature}{params}[0]{sigil}, '%', 'the param is a hash';
};

subtest 'mandatory plus slurpy keeps both' => sub {
    my $rec = sig_for( 'sub mix($a,@r) { $a + @r } print mix(1,2,3), "\n";',
        'mix', 'mix' );
    ok $rec, 'recorded' or return;
    is $rec->{signature}{mandatory}, 1, 'one mandatory';
    is $rec->{signature}{slurpy},  '@', 'and a slurpy array';
    my $p = $rec->{signature}{params};
    is scalar @$p, 2, 'two parameter records' or return;
    is $p->[0]{sigil}, '$', 'first is the scalar';
    is $p->[1]{sigil}, '@', 'second is the slurpy';
};

# `sub f {}` and `sub f() {}` are EXACTLY DIFFERENT (perigrin). Signature-less
# is the most PERMISSIVE declaration; empty-signature the most RESTRICTIVE.
# Verified against perl: `sub empty() {} empty(1)` dies "Too many arguments for
# subroutine 'main::empty' (got 1; expected 0)".
subtest 'an empty signature is arity zero, ENFORCED' => sub {
    my $rec = sig_for( 'sub empty() { 43 } print empty(), "\n";',
        'empty', 'empty' );
    ok $rec, 'recorded' or return;
    is $rec->{signature}{kind}, 'declared', 'declared, not absent';
    is $rec->{signature}{mandatory}, 0, 'zero mandatory';
    ok !$rec->{signature}{slurpy}, 'and NOT slurpy -- takes nothing at all';
    is scalar $rec->{signature}{params}->@*, 0, 'no parameter records';
};

subtest 'a signature-less sub is implicitly (@_)' => sub {
    my $rec = sig_for( 'sub none { 42 } print none(), "\n";', 'none', 'none' );
    ok $rec, 'recorded' or return;
    is $rec->{signature}{kind}, 'implicit',
        'kind distinguishes it from a declared signature';
    is $rec->{signature}{slurpy}, '@',
        'implicitly slurpy: `sub f {}` is `sub f(@_)`';
    my $p = $rec->{signature}{params};
    is scalar @$p, 1, 'one implicit parameter' or return;
    is $p->[0]{name}, '@_', 'and it is @_';
    is $p->[0]{index}, 0,   'at index 0';
};

# A method's invocant is NOT a parameter: perl emits methstart() for it and
# argcheck counts only the declared params, so $k is argelem(0). No reserved
# index is needed in either direction.
subtest 'a method invocant is separate; user params start at 0' => sub {
    my $wire = wire_for(
        'use experimental "class"; class C { method m($k) { $k } } print C->new->m(2), "\n";',
        'meth' );
    my $cls = $wire->{classes}{C} // {};

    # The method VALUE stays a graph-name string: consumers in both repos use it
    # directly as a key into the top-level {methods} graph map. The signature
    # rides in a sibling map, which is additive.
    is ref( $cls->{methods}{m} ), '',
        'the method value is still a plain graph-name string';
    ok exists $wire->{methods}{ $cls->{methods}{m} },
        'and it still keys a real graph';

    my $rec = ( $cls->{method_signatures} // {} )->{m};
    is ref($rec), 'HASH', 'the signature rides in method_signatures' or return;
    $rec = { signature => $rec };
    is $rec->{signature}{mandatory}, 1, 'argcheck counts ONE param, not two';
    is $rec->{signature}{params}[0]{index}, 0, '$k is index 0, not 1';
    is $rec->{signature}{params}[0]{name}, '$k', 'and it is $k';
    ok $rec->{signature}{invocant}, 'the invocant is recorded separately';
};

done_testing;
