# ABOUTME: An aggregate flattened into a list, with a later item that may store into its elements (its own
# ABOUTME: store, a map writing $_, a call), is refused by name (audit 2, K7): perl's list holds the elements.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

# THE DEFECT (second final audit, class K7): `my @b = (@a, $a[0] = 9)` is
# `9 2 3 9` in perl -- the list holds @a's elements, read when it is used --
# and the graph flattened the literal's constants, `1 2 3 9`.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub compile ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>&1);
}
my $gap = qr/GAP: an aggregate flattened into a list is read by alias and a later item may store into its elements/;
like compile($_), $gap, "refused: $_" for
    'my @a=(1,2,3); my @b=(@a, $a[0]=9); print "@b\n";',
    'my @a=(1,2,3); print "@{[ @a, $a[0]++ ]}\n";',
    'my @a=(1,2,3); my @b=(@a, map { $_++ } @a); print "@b\n";',
    'my @a=(1,2,3); sub g { $a[0]=9 } my @b=(@a, g()); print "@b\n";',
    'my %h=(a=>1); my @b=(%h, $h{a}=9); print "@b\n";';
unlike compile($_), qr/GAP/, "lowered: $_" for
    'my @a=(1,2,3); my @b=(@a, map { $_*2 } @a); print "@b\n";',
    'my @a=(1,2,3); my @b=(@a, $a[0]); print "@b\n";',
    'my @a=(1,2,3); my @c=(4); my @b=(@a, $c[0]=9); print "@b\n";';
done_testing;
