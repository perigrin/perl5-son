# ABOUTME: An assignment or a ?: of two `my` scalars as the target of another store is lowered
# ABOUTME: (design 3); a ?: of anything else, or a string op= of an assignment, a GAP by name.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub translate ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    my $json = qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>$dir/err);
    open my $e, '<', "$dir/err" or die $!;
    return join '', <$e>;
}

# Each of these printed perl's answer before the outer store; the outer store
# itself reached no node and no GAP (`($x = 5) += 2` printed 5 for 7). Then
# each was refused by name. The outer op stores into the inner one's target;
# a ?: of two `my` scalars stores in each arm (docs/plans/2026-11-24-aliases-as-places.md).
my $NAME = qr/GAP: (?:an assignment|a \?:) used as the target of/;
for my $src (
    'my $x=1; ($x += 2) *= 3; print "$x\n";',
    'my ($a,$b)=(1,2); my $c=1; ($c ? $a : $b) = 9; print "$a$b\n";',
    'my $x=1; ($x = 5) += 2; print "$x\n";',
    'my $x=1; (my $y = $x) += 5; print "$x$y\n";',
    'my $x=1; my $y = (($x += 2) *= 3); print "$x$y\n";',
    'our $x=1; ($x += 2) *= 3; print "$x\n";',
    'my @a=(1); ($a[0] += 2) *= 3; print "@a\n";',
    'my $x=1; sub inc { $_[0]++ } inc($x += 1); print "$x\n";',
    'my ($a,$b)=(1,2); my $c=1; ($c ? $a : $b)++; print "$a$b\n";',
    'my @a=(1,2,3); (my $t = $a[0]) *= 10; print "$t @a\n";',
    'my $x=5; ($x -= 1) /= 2; print "$x\n";',
    'my ($a,$b)=(1,2); my $c=1; ($c ? $a : $b) = ($c ? $b : $a) + 5; print "$a$b\n";',
) {
    unlike translate($src), qr/GAP:/, "not refused: $src";
}
# Refused by name: a ?: whose arm is a package scalar or another ?: (the store
# in each arm would need an If), and a string op= of an assignment.
for my $src (
    'our ($a1,$b1)=(1,2); my $c=1; ($c ? $a1 : $b1) = 9; print "$a1$b1\n";',
    'my ($p,$q,$r)=(1,2,3); my $c=0; ($c ? $p : $c ? $q : $r) = 9; print "$p$q$r\n";',
    'my $x; ($x = 1) .= "z"; print "$x\n";',
) {
    like translate($src), $NAME, "refused by name: $src";
}

# The shapes with a handler stay translated.
for my $src (
    'my ($x,$y)=("","ab"); ($x = $y) =~ s/a/b/; print "$x$y\n";',
    'my $x=1; $x += 2; $x *= 3; print "$x\n";',
    'my $x; my $y = ($x = 5); print "$x$y\n";',
    'my ($a,$b)=(1,2); my $c=1; my $v = $c ? $a : $b; print "$v\n";',
) {
    unlike translate($src), qr/GAP:/, "not refused: $src";
}

done_testing;
