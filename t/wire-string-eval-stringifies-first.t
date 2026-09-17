# ABOUTME: `eval EXPR` stringifies its operand, then compiles the string.
# ABOUTME: one Coerce(Scalar -> Code) hides a step perl observably performs.
use 5.42.0;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir( CLEANUP => 1 );

sub translate ( $src, $name ) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>/dev/null};
    return length $json ? JSON::PP->new->decode($json) : undef;
}

sub nodes ( $wire ) {
    return ( ( $wire->{methods}{'main::__PROGRAM__'} // {} )->{nodes} // [] );
}

# THE STRINGIFICATION IS OBSERVABLE, which is what makes it a step rather than
# an implementation detail. Measured on 5.42.0 with an overloaded object:
#
#     package O; use overload q{""} => sub { "1+1" }, fallback => 1;
#     my $r = eval bless({}, "O");        $r is 2
#
# perl called `""` to get "1+1" and compiled THAT. So `eval EXPR` is two
# conversions -- stringify, then compile -- and collapsing them into one
# Coerce(Scalar -> Code) claims a Scalar becomes Code directly.
#
# The nesting is the honest spelling:
#
#     Coerce( Coerce($src Scalar -> Str) -> Code )
#
# and it matters to a consumer: the inner conversion is one any T2 can already
# lower (stringification is ordinary), while only the OUTER one is the
# un-lowerable "compile arbitrary perl". Fused, a consumer cannot tell which
# half it is refusing.
subtest 'an eval of a non-Str operand stringifies first' => sub {
    my $wire = translate( <<'SRC', 'ext' );
my $c = <STDIN>;
my $r = eval $c;
print "$r\n";
SRC
    ok $wire, 'it translates' or return;

    my @n = nodes($wire)->@*;
    my %by = map { $_->{id} => $_ } @n;

    my ($code) = grep { ( $_->{op} // '' ) eq 'Coerce'
        && ( $_->{fields}{to_repr} // '' ) eq 'Code' } @n;
    ok $code, 'a Coerce to Code is in the graph' or return;

    is( ( $code->{fields}{from_repr} // '' ), 'Str',
        'the compile step takes a Str, not a raw Scalar' );

    my $inner = $by{ ( $code->{inputs} // [] )->[0] // -1 };
    ok $inner, 'its operand resolves' or return;
    is( ( $inner->{op} // '' ), 'Coerce',
        'and the operand is itself a Coerce -- the stringification' );
    is( ( $inner->{fields}{to_repr} // '' ), 'Str',
        '... which produces the Str' );
};

# A Str OPERAND NEEDS NO STRINGIFICATION, and inserting one would be noise.
# `eval "1 + 2"` is already a string; there is nothing to convert.
subtest 'an eval of a Str operand gets no extra Coerce' => sub {
    my $wire = translate( 'my $r = eval "1 + 2"; print "$r\n";', 'lit' );
    ok $wire, 'it translates' or return;

    my @n = nodes($wire)->@*;
    my %by = map { $_->{id} => $_ } @n;

    my ($code) = grep { ( $_->{op} // '' ) eq 'Coerce'
        && ( $_->{fields}{to_repr} // '' ) eq 'Code' } @n;
    ok $code, 'a Coerce to Code is in the graph' or return;
    is( ( $code->{fields}{from_repr} // '' ), 'Str', 'it takes a Str' );

    my $inner = $by{ ( $code->{inputs} // [] )->[0] // -1 };
    ok $inner, 'its operand resolves' or return;
    isnt( ( $inner->{op} // '' ), 'Coerce',
        'the literal is compiled directly -- no stringify step' );
};

# THE DISCRIMINATING FACT SURVIVES THE NESTING. A consumer still separates a
# compile-time-known eval from an external one by walking to the SOURCE; the
# extra Coerce is one more hop, not a lost distinction.
subtest 'the source is still reachable through the nesting' => sub {
    my $wire = translate( <<'SRC', 'reach' );
my $c = <STDIN>;
my $r = eval $c;
print "$r\n";
SRC
    ok $wire, 'it translates' or return;

    my @n = nodes($wire)->@*;
    my %by = map { $_->{id} => $_ } @n;
    my ($code) = grep { ( $_->{op} // '' ) eq 'Coerce'
        && ( $_->{fields}{to_repr} // '' ) eq 'Code' } @n;
    ok $code, 'a Coerce to Code is in the graph' or return;

    # Walk down through any Coerce chain to the real producer.
    my $src = $by{ ( $code->{inputs} // [] )->[0] // -1 };
    $src = $by{ ( $src->{inputs} // [] )->[0] // -1 }
        while $src && ( $src->{op} // '' ) eq 'Coerce';

    ok $src, 'the source resolves' or return;
    is( ( $src->{op} // '' ), 'Call', 'an external eval bottoms out in a Call' );
    is( ( $src->{fields}{name} // '' ), 'readline', '... to readline' );
};

done_testing;
