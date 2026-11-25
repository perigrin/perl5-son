# ABOUTME: An assignment, op= or pre-increment of an element used as an operand, with a later operand
# ABOUTME: storing into that element's container, is refused by name (audit 2, K5): perl reads the element.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

# THE DEFECT (second final audit, class K5): `($a[0] = 5) + ($a[0] = 7)` is
# 14 in perl -- each operand is the element, read when the add runs -- and
# the graph added the two values, 12. The scalar form (`($x += 1) + ($x +=
# 1)`) was already refused; the element form was not.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub compile ($src) {
    my $f = "$dir/p" . ++$n . '.pl';
    open my $o, '>', $f or die $!;
    print $o $src;
    close $o;
    return scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>&1);
}
my $gap = qr/GAP: an assignment's element is read by alias and a later operand stores into its container/;
like compile($_), $gap, "refused: $_" for
    'my @a=(1,2,3); my $n = ($a[0] += 1) + ($a[0] += 1); print "$n\n";',
    'my %h=(a=>1); my $n = ($h{a} += 1) + ($h{a} += 1); print "$n\n";',
    'my @a=(1); my $n = ($a[0] = 5) + ($a[0] = 7); print "$n\n";',
    'my @a=(1); my $n = ++$a[0] + ++$a[0]; print "$n\n";',
    'my @a=(1); my @l=(++$a[0], ++$a[0]); print "@l\n";';
unlike compile($_), qr/GAP/, "lowered: $_" for
    'my @a=(1); my $n = ($a[0] += 1) + 1; print "$n\n";',
    'my @a=(1); my @b=(2); my $n = ($a[0] = 5) + ($b[0] = 7); print "$n\n";';
done_testing;
