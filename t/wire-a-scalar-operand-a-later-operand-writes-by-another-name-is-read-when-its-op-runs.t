# ABOUTME: An operand perl reads by alias -- `++$x`'s result, a `my` scalar or element a reference
# ABOUTME: reaches -- written by a later operand of the same op: read when the op runs (perl's answer).
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use lib 't/lib';
use PerlAnswer;

my $dir = tempdir(CLEANUP => 1);

sub warnings_of ($src) {
    my $f = "$dir/g.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    return scalar qx($^X -Ilib -MO=-q,SoN,json,not_package=SoN $f 2>&1 >/dev/null);
}

# RE-AUDIT 2026-11-23, class G (probes/r j33, j49, q21-q27): a scalar operand
# is read again when a later operand stores it by name; not when the operand is
# a pre-increment (whose result is the variable), nor when the store is through
# a reference -- `my $x=5; my @l=(++$x, ++$x)` gave 6 7 for perl's 7 7, and
# `my $x=1; my $r=\$x; my $v = $x + ($$r=5)` gave 6 for perl's 10.
#
# READ WHEN ITS OP RUNS, since places-everywhere (audit 3, N4/N7): each operand
# perl pushed by alias is read again at the version its consumer runs at -- a
# pre-increment's result is the variable, a store through a reference stores
# the scalar the name reads. Was a refusal by name; now perl's answer, with
# the promotion pass and without it.
my %lowered = (
    'pre-increments in a list'     => 'my $x=5; my @l=(++$x, ++$x); print "@l\n";',
    'a pre- then a post-increment' => 'my $x=5; my @l=(++$x, $x++); print "@l\n";',
    'pre-increments multiplied'    => 'my $x=5; my $y = ++$x * ++$x; print "$y\n";',
    'a pre-increment added'        => 'my $x=5; my $y = ++$x + $x++; print "$y $x\n";',
    'a pre-increment joined'       => 'my $x=5; my $s = ++$x . $x++; print "$s\n";',
    'a store through a reference'  => 'my $x=1; my $r=\$x; my $v = $x + ($$r=5); print "$v\n";',
    'printed beside such a store'  => 'my $x=1; my $r=\$x; print $x, ($$r=2), "\n";',
    'in a list'                    => 'my $x=1; my $r=\$x; my @l=($x, ($$r=2), $x); print "@l\n";',
    'an element, by its reference' => 'my @a=(1); my $r=\@a; my @l=($a[0], ($r->[0]=2), $a[0]); print "@l\n";',
);
answers_like_perl( $lowered{$_}, $_ ) for sort keys %lowered;

# Read again, as before: a store by the variable's own name.
unlike warnings_of('my $n = 1; print $n . ($n = 5), "\n";'), qr/GAP:/, 'a store by name is read again';
unlike warnings_of('my $x=5; my $y = ++$x + 1; print "$y\n";'), qr/GAP:/, 'a pre-increment nothing later stores';

done_testing;
