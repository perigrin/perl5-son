# ABOUTME: Braun's scan (wire v2 stage 9b) gives no header Phi to an array whose elements a loop
# ABOUTME: stores: the read after the loop reads memory, not the literal the array was made from.
use v5.42.0;
use Test2::V0;
use JSON::PP;
use File::Temp qw(tempdir);

# WHY. A Phi for @a stood where the list assign into its elements looked at
# @a's binding: the walk marks a literal mutated by its class, a Phi is no
# literal, nothing was marked, and `print "@a"` after the loop flattened
# (1, 2) -- perl prints `4 5`, chalk printed `1 2` (t2-a-list-assign-into-
# elements-slices-and-cells.t, "in a loop"). An element store changes
# memory, not what @a is bound to.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub wire ($src) {
    my $f = "$dir/p" . ++$n . ".pl";
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return JSON::PP->new->utf8->decode( scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>$dir/err) );
}

for my $src (
    q{my @a = (1,2); for my $i (1 .. 3) { ($a[0], $a[1]) = ($a[1], $a[0] + $i) } print "@a\n";},
    q{my @a = (1,2); for my $i (1 .. 3) { $a[0] = $a[1] + $i } print "@a\n";},
    q{my %h = (a => 1); for my $i (1 .. 3) { @h{qw(a b)} = ($i, $i) } print join(",", map { "$_=$h{$_}" } sort keys %h), "\n";},
) {
    my $nodes = wire($src)->{methods}{'main::__PROGRAM__'}{nodes};
    my %by = map { $_->{id} => $_ } @$nodes;
    my ($L) = grep { $_->{op} eq 'Loop' } @$nodes;
    my @phis = grep { $_->{op} eq 'Phi' && !( $_->{fields} // {} )->{memory} && ( $_->{fields}{region} // -1 ) == $L->{id} } @$nodes;
    ok !( grep { ( $by{ $_->{inputs}[0] }{op} // '' ) =~ /\A(?:Array|Hash)Literal\z/ } @phis ), "$src: no loop Phi of the aggregate";
    my ($join) = grep { $_->{op} eq 'Call' && ( $_->{fields}{name} // '' ) eq 'join' } @$nodes;
    ok defined $join->{mem_in}, '... and the read after the loop names a version' if $src =~ /"\@a/;
}

done_testing;
