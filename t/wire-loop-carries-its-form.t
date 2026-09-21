# ABOUTME: perl's loop forms disagree about re-reading a mutated bound.
# ABOUTME: the producer knows which form it built; the wire has to say so.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

my $dir = tempdir( CLEANUP => 1 );

sub graph_of ($src) {
    my $f = "$dir/g." . int( rand 1e9 ) . ".pl";
    open my $fh, '>', $f or die $!;
    print $fh $src;
    close $fh;
    my $j = qx($^X -Ilib -MO=SoN,json,package=main $f 2>$dir/err);
    my $e = do { open my $h, '<', "$dir/err"; local $/; <$h> } // '';
    unlink $f;
    return ( eval { JSON::PP->new->decode($j) }, $e );
}

sub loops ( $wire ) {
    return [ grep { ( $_->{op} // '' ) eq 'Loop' }
             ( ( $wire->{methods}{'main::__PROGRAM__'} // {} )->{nodes} // [] )->@* ];
}

# THE TWO FORMS DISAGREE, measured on 5.42.0:
#
#     $n=2; foreach my $i (1..$n) { $n = 10; ... }    2 iterations
#     $n=2; for ($i=0; $i<$n; $i++) { $n = 4; ... }   4 iterations
#
# perl evaluates a foreach RANGE's endpoints ONCE, when the loop is entered,
# and iterates the fixed list that produces. A C-style `for` runs its
# condition every pass. So a consumer that hoists the bound to a temporary is
# CORRECT for the range form and WRONG for the C-style one -- and a consumer
# that never hoists is the reverse (measured: re-reading a global the body
# mutates makes the bound chase the counter, which is what
# t/deparse-loop-bound-is-evaluated-once.t pins).
#
# THE PRODUCER KNOWS WHICH IT BUILT -- _translate_foreach_range and the
# C-style path through _translate_while_loop are separate translators -- and
# dropped the fact. Three derivations were tried against the graph and none
# separated them: reaching a loop Phi (blind to package variables, whose
# updates ride the memory chain), whether the body writes the variable (true
# of both), and the condition's memory version (BOTH read the pre-loop
# EntryWrite). The C-style condition is not even pinned to the Loop, and
# keying on that ABSENCE is the trap this project has hit before.
#
# So the Loop says which form it is.
subtest 'a foreach range says its bound is fixed at entry' => sub {
    my ( $wire, $err ) = graph_of( 'our $n = 3; foreach my $i (1..$n) { print "$i\n" }' );
    ok $wire, 'it translates' or diag($err), return;

    my ($loop) = loops($wire)->@*;
    ok $loop, 'a Loop is in the graph' or return;
    is( ( $loop->{fields}{bound} // '' ), 'entry',
        'the range form fixes its bound at entry' );
};

subtest 'a C-style for says its condition is re-read' => sub {
    my ( $wire, $err ) = graph_of( 'for ($i = 0; $i < 3; $i++) { print "$i\n" }' );
    ok $wire, 'it translates' or diag($err), return;

    my ($loop) = loops($wire)->@*;
    ok $loop, 'a Loop is in the graph' or return;
    is( ( $loop->{fields}{bound} // '' ), 'each',
        'the C-style form re-reads every pass' );
};

subtest 'a while says its condition is re-read' => sub {
    my ( $wire, $err ) = graph_of( 'my $j = 0; while ($j < 3) { $j++ } print "$j\n";' );
    ok $wire, 'it translates' or diag($err), return;

    my ($loop) = loops($wire)->@*;
    ok $loop, 'a Loop is in the graph' or return;
    is( ( $loop->{fields}{bound} // '' ), 'each',
        'a while re-reads every pass' );
};

subtest 'a foreach over an array fixes its bound too' => sub {
    my ( $wire, $err ) = graph_of(
        'my @a = (1,2,3); foreach my $x (@a) { print "$x\n" }' );
    ok $wire, 'it translates' or diag($err), return;

    my ($loop) = loops($wire)->@*;
    ok $loop, 'a Loop is in the graph' or return;
    is( ( $loop->{fields}{bound} // '' ), 'entry',
        'the array form fixes its length at entry' );
};

done_testing;
