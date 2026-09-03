# ABOUTME: NaN and Inf are Str, not Num -- they fail the semantic component.
# ABOUTME: _extract_const stamps from SVf_NOK, which cannot see the value.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $PERL = $^X;
my $dir  = tempdir(CLEANUP => 1);

sub const_stamps ($src, $name) {
    my $file = "$dir/$name.pl";
    open my $fh, '>', $file or die "open $file: $!";
    print {$fh} "use 5.42.0;\nno warnings;\n$src\n";
    close $fh;
    my $json = qx{$PERL -Ilib -MO=SoN,json,package=main $file 2>$dir/$name.err};
    die "no JSON emitted for $name" unless length $json;
    my $wire = JSON::PP->new->decode($json);
    return [ map { { ($_->{fields} // {})->%*, stamp => $_->{stamp} } }
             grep { $_->{op} eq 'Constant' }
             ($wire->{methods}{'main::__PROGRAM__'}{nodes} // [])->@* ];
}

sub stamp_of ($stamps, $want) {
    my ($c) = grep { defined $_->{value} && "$_->{value}" eq $want } $stamps->@*;
    return $c && $c->{stamp};
}

# NaN AND Inf FAIL THE SEMANTIC COMPONENT OF Num MEMBERSHIP. They pass the
# syntactic test -- "NaN" round-trips to "NaN", "Inf" to "Inf" -- and fail on
# the operation contracts, measured on 5.42.0:
#
#     NaN == NaN   false        Contract_== violated (an equality reporting
#                               x != x has failed AS an equality)
#     NaN - NaN    NaN          Contract_- violated (v - v is not the additive
#                               identity)
#     Inf == Inf   true         Contract_== holds
#     Inf - Inf    NaN          Contract_- violated
#
# So both are Str and NOT Num. perl-types-formal.md states this directly: its
# contract table marks NaN and Inf `excluded`, and Theorem 3 derives
# `"NaN" is not in Num` from the semantic component alone.
#
# THE PRODUCER COULD NOT SEE IT. _extract_const dispatches on the SV's flags,
# and SVf_NOK is set for every float alike -- 3.14, Inf and NaN are
# indistinguishable at the flag level. The value has to be tested.
subtest 'Inf is not stamped Num' => sub {
    my $s = const_stamps('my $x = 9**9**9; print $x;', 'inf');
    my $st = stamp_of($s, 'Inf');
    ok defined $st, 'the Inf constant reaches the wire' or return;
    isnt $st, 'Num', 'Inf is not Num -- Inf - Inf is NaN, so Contract_- fails';
    is $st, 'Str', 'it is a Str: "Inf" survives the syntactic round trip';
};

subtest 'NaN is not stamped Num' => sub {
    my $s = const_stamps('my $x = 9**9**9 - 9**9**9; print $x;', 'nan');
    my $st = stamp_of($s, 'NaN');
    ok defined $st, 'the NaN constant reaches the wire' or return;
    isnt $st, 'Num', 'NaN is not Num -- NaN != NaN, so Contract_== fails';
    is $st, 'Str', 'it is a Str: "NaN" survives the syntactic round trip';
};

# EVERY ORDINARY FLOAT MUST STILL BE Num. This is the guard that matters: a
# fix that simply stopped stamping NOK constants as Num would satisfy both
# subtests above and destroy all float typing.
subtest 'ordinary floats are still Num' => sub {
    my $s = const_stamps('my $a = 3.14; my $b = -0.5; my $c = 1e10; print $a+$b+$c;', 'floats');
    is stamp_of($s, '3.14'), 'Num', '3.14 is Num';
    is stamp_of($s, '-0.5'), 'Num', '-0.5 is Num';
    is stamp_of($s, '10000000000'), 'Num', '1e10 is Num';
};

# AND INTEGERS ARE UNTOUCHED -- they take the IOK arm, which this change does
# not go near.
subtest 'integers are still Int' => sub {
    my $s = const_stamps('my $n = 42; print $n;', 'ints');
    is stamp_of($s, '42'), 'Int', '42 is Int';
};

# ZERO IS THE ADVERSARIAL CASE for a naive `$v != $v` NaN test written as a
# truthiness check: 0.0 is falsy but perfectly well-behaved, and 0 == 0.
subtest 'zero and negative zero are Num' => sub {
    my $s = const_stamps('my $z = 0.0; my $n = -0.0; print $z+$n;', 'zeros');
    for my $c ($s->@*) {
        next unless defined $c->{value} && $c->{value} =~ /^-?0$/;
        is $c->{stamp}, 'Num', "$c->{value} is Num, not misread as non-finite";
    }
    pass('no zero constant reached the wire') unless grep {
        defined $_->{value} && $_->{value} =~ /^-?0$/ } $s->@*;
};

done_testing;
