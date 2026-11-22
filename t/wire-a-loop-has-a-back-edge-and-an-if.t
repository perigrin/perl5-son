# ABOUTME: Wire v2's `loop` profile: a Loop has inputs [entry, back], the back input the last
# ABOUTME: control of a pass; its test is an If on the Loop (or on the test's last effect).
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

# docs/plans/2026-11-20-wire-v2.md, section 3.6, as facts about the nodes:
#
#   our $g = 0; my $i = 0; while ($i < 3) { $g = $g + $i; $i++ } print "$g\n";
#
# v1 had `Loop [entry]`, the test pinned to the Loop and two Projs on it; the
# back edge was on the Phis alone.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub wire ($src) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return JSON::PP->new->utf8->decode( scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>$dir/err) );
}
sub graph ( $w, $name = 'main::__PROGRAM__' ) {
    my @n = $w->{methods}{$name}{nodes}->@*;
    return ( \@n, { map { $_->{id} => $_ } @n } );
}
sub f ( $x, $k ) { ( $x->{fields} // {} )->{$k} }
sub of ( $nodes, $op ) { grep { $_->{op} eq $op } @$nodes }
sub projs ( $nodes, $of ) { map { f( $_, 'index' ) => $_ } grep { $_->{op} eq 'Proj' && $_->{inputs}[0] == $of->{id} } @$nodes }

# every Loop of a wire keeps the profile's rules: no Proj on it, one or two
# inputs, its Phis one input per input
sub loop_rules ( $w, $what ) {
    for my $g ( sort keys $w->{methods}->%* ) {
        my ( $nodes, $by ) = graph( $w, $g );
        for my $L ( of( $nodes, 'Loop' ) ) {
            my $k = scalar $L->{inputs}->@*;
            ok $k == 1 || $k == 2, "$what ($g): Loop#$L->{id} has one or two inputs";
            ok !( grep { $_->{op} eq 'Proj' && $_->{inputs}[0] == $L->{id} } @$nodes ), "... and no Proj";
            ok !defined $L->{control_in}, '... and no control_in beside its way in';
            my @bad = grep { $_->{op} eq 'Phi' && ( f( $_, 'region' ) // -1 ) == $L->{id} && $_->{inputs}->@* != $k } @$nodes;
            is [ map { $_->{id} } @bad ], [], '... and each of its Phis one input per way in';
        }
    }
}

my $w = wire(q{our $g = 0; my $i = 0; while ($i < 3) { $g = $g + $i; $i++ } print "$g\n";});
ok( ( grep { $_ eq 'loop' } $w->{profile}->@* ), 'the wire says it obeys the loop profile' );
loop_rules( $w, 'the 3.6 loop' );
{
    my ( $nodes, $by ) = graph($w);
    my ($L) = of( $nodes, 'Loop' );
    is scalar $L->{inputs}->@*, 2, 'the Loop has two inputs: the way in and the way round';
    my $back = $by->{ $L->{inputs}[1] };
    is $back->{op}, 'EntryWrite', '... the way round is the body\'s last control: the store of $g';
    my ($if) = grep { $_->{inputs}[0] == $L->{id} } of( $nodes, 'If' );
    ok $if, 'the test is an If on the Loop' or last;
    my $cond = $by->{ $if->{inputs}[1] };
    is $cond->{op}, 'NumLt', '... of the comparison';
    ok !defined $cond->{control_in}, '... which is an ordinary value, pinned to nothing';
    my %p = projs( $nodes, $if );
    is $back->{control_in}, $p{0}{id}, 'Proj 0 of the If is the body';
    my ($exit) = grep { $_->{op} eq 'Region' && ( $_->{head} // -1 ) == $L->{id} } @$nodes;
    is $exit->{inputs}, [ $p{1}{id} ], 'Proj 1 is the way out, into the exit Region headed by the Loop';
    my ($mphi) = grep { f( $_, 'memory' ) && f( $_, 'region' ) == $L->{id} } of( $nodes, 'Phi' );
    is $mphi->{inputs}, [ $L->{inputs}[0], $back->{id} ], 'the header memory Phi: the memory before the loop, and the store';
}

# A TEST WITH AN EFFECT: the shift is pinned on the Loop, the If on the shift.
{
    my ( $nodes, $by ) = graph( my $w2 = wire(q{my @w = (1, 2); while (my $n = shift @w) { print $n }}) );
    loop_rules( $w2, 'a test with an effect' );
    my ($L)  = of( $nodes, 'Loop' );
    my ($sh) = grep { ( f( $_, 'name' ) // '' ) eq 'shift' } of( $nodes, 'Call' );
    is $sh->{control_in}, $L->{id}, 'the condition\'s effect is pinned on the Loop';
    my ($if) = of( $nodes, 'If' );
    is $if->{inputs}[0], $sh->{id}, '... and the If on it';
    is $by->{ $if->{inputs}[1] }{op}, 'NumNe', '... testing its value';
    my ($pr) = of( $nodes, 'Print' );
    is $L->{inputs}[1], $pr->{id}, 'the way round: the print, the body\'s last control';
}

# EACH TRANSLATOR: range and array foreach, a while(1) with a `last` at its
# head and one mid-body, a `next` (the latch is a Region), a C-style for, a
# postfix `redo` spin and a backward computed goto.
my %src = (
    'a range foreach'         => q{my $s = 0; for my $i (1..3) { $s += $i } print "$s\n";},
    'an array foreach'        => q{my @a = (1,2,3); my $s = 0; for my $x (@a) { $s += $x } print "$s\n";},
    'a map'                   => q{my @a = map { $_ * 2 } (1,2,3); print "@a\n";},
    'a last at the head'      => q{my $i = 0; while (1) { last if $i > 3; $i++ } print "$i\n";},
    'a last mid-body'         => q{my $i = 0; while (1) { $i++; last if $i > 3 } print "$i\n";},
    'a next'                  => q{my $s = 0; for my $i (1..5) { next if $i == 2; $s += $i } print "$s\n";},
    'a C-style for'           => q{my $s = 0; for (my $i = 0; $i < 4; $i++) { $s += $i } print "$s\n";},
    'an until'                => q{my $i = 0; $i++ until $i >= 3; print "$i\n";},
    'a postfix redo'          => q{my $x = 0; { redo if $x > 5; print "y\n" }},
    'a computed goto back'    => q{my $t = $ENV{T} // "B"; A: print "a\n"; goto $t; B: print "b\n";},
);
for my $what ( sort keys %src ) {
    my $w = wire( $src{$what} );
    ok $w->{methods}, "$what: a wire" or next;
    loop_rules( $w, $what );
}

# THE BACK INPUT OF A LOOP WITH A `next` is the latch Region where the next
# and the body's end meet.
{
    my ( $nodes, $by ) = graph( wire( $src{'a next'} ) );
    my ($L) = of( $nodes, 'Loop' );
    my $back = $by->{ $L->{inputs}[1] // '' };
    is $back && $back->{op}, 'Region', 'a `next`: the way round is the latch Region';
}

# THE TEST OF A while(1) WHOSE BODY OPENS WITH `last if C` is that guard,
# negated, as an If on the Loop.
{
    my ( $nodes, $by ) = graph( wire( $src{'a last at the head'} ) );
    my ($L) = of( $nodes, 'Loop' );
    my ($if) = grep { $_->{inputs}[0] == $L->{id} } of( $nodes, 'If' );
    ok $if, 'a `last if` at the head: the If on the Loop';
}

done_testing;
