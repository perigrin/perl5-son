# ABOUTME: A BLOCK operand must never be dropped: map/grep lower it, sort refuses.
# ABOUTME: Shipping the list without the transform is a silent wrong answer.
use 5.42.0;
use utf8;
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
    my $json = qx{$PERL -Ilib -MO=SoN,json $file 2>$dir/$name.err};
    my $err  = do { open my $e, '<', "$dir/$name.err"; local $/; <$e> } // '';
    return ( ( length $json ? JSON::PP->new->decode($json) : undef ), $err );
}

sub ops ( $w ) {
    return [ map { $_->{op} // '' }
             map { ( $w->{methods}{$_}{nodes} // [] )->@* }
             sort keys( ( $w->{methods} // {} )->%* ) ];
}

# THE DEFECT, reported by chalk against corpus F18/F19/F20. `map { $_ * 2 }`
# emitted a well-formed graph with the LIST but not the BLOCK, and no
# diagnostic at all:
#
#     Start, Constant x3, Call(mapstart), ArrayLiteral, MemStart,
#     Subscript, Coerce, Print, Return
#
# No Multiply anywhere -- the `* 2` is absent in every form. The cause is in
# OpMap: `mapstart` maps to a generic Call that consumes the list, and
# `mapwhile` -- which IS the block execution -- is marked BRANCH, so the
# generic branch-skip steps over the body without walking it.
#
# A silent drop is the worst outcome the refuse-or-lower contract exists to
# prevent: the consumer sees a complete graph that computes the wrong thing.
# chalk only escaped it by refusing `mapstart` for an unrelated reason (not in
# its arithmetic slice); with a mapstart arm it would have emitted a program
# returning the unmapped list.
# map and grep are now LOWERED rather than refused -- as loops with a
# ListAppend accumulator, which is what makes a variable-length output
# expressible. The contract this file exists to protect is unchanged, and is
# asserted here in its positive form: THE BLOCK'S COMPUTATION IS IN THE GRAPH.
# The original defect was a graph with no Multiply in it anywhere.
subtest 'map lowers its block rather than dropping it' => sub {
    my ( $w, $err ) = translate(
        'my @m = map { $_ * 2 } (1,2); print $m[1];', 'map-block' );
    ok $w, 'it translates' or diag($err), return;
    my $ops = ops($w);
    ok scalar( grep { $_ eq 'Multiply' } $ops->@* ),
        "the block's `* 2` is in the graph -- the original defect was its absence";
    ok scalar( grep { $_ eq 'ListAppend' } $ops->@* ),
        '... accumulated, so the output length is not forced to the input length';
};

subtest 'grep lowers its predicate rather than dropping it' => sub {
    my ( $w, $err ) = translate(
        'my @g = grep { $_ > 1 } (1,2,3); print scalar(@g);', 'grep-block' );
    ok $w, 'it translates' or diag($err), return;
    my $ops = ops($w);
    ok scalar( grep { $_ eq 'NumGt' } $ops->@* ), "the predicate is in the graph";
    ok scalar( grep { $_ eq 'ListAppend' } $ops->@* ),
        '... gating a ListAppend, which is how a filter shortens the list';
};

# `sort` ONLY CARRIES A BLOCK WHEN PERL COULD NOT FOLD IT, which makes it
# different from map/grep. Measured:
#
#     sort { $a <=> $b }            lK/NUM       folded to a flag, no block
#     sort { $b <=> $a }            lK/DESC,NUM  folded, no block
#     sort { length($a) <=> ... }   lKS*         OPf_STACKED, a real subtree
#
# So the standard numeric comparators are not refused -- there is nothing to
# drop -- and only an unfoldable comparator is.
subtest 'sort with an UNFOLDABLE comparator block refuses' => sub {
    my ( undef, $err ) = translate(
        'my @s = sort { length($a) <=> length($b) } ("aa","b"); print $s[0];',
        'sort-block' );
    like $err, qr/GAP:/, 'refused';
    like $err, qr/comparator/, '... naming the comparator';
};

subtest 'a folded numeric comparator is not refused for a block' => sub {
    my ( undef, $err ) = translate(
        'my @s = sort { $a <=> $b } (3,1); print $s[0];', 'sort-folded' );
    unlike $err, qr/comparator BLOCK/,
        'perl folded it to a NUM flag -- there is no block to drop';
};

# THE REFUSAL MUST BE ABOUT THE BLOCK, not about map itself. `sort` with no
# comparator has no block to lower and should not be caught by this.
subtest 'sort without a block is not caught by the block refusal' => sub {
    my ( $w, $err ) = translate(
        'my @s = sort (3,1,2); print $s[0];', 'sort-plain' );
    unlike $err, qr/block/, 'a blockless sort is not refused for having a block';
};

done_testing;
