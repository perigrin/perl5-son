# ABOUTME: An assignment, op= or pre-increment of an element used as an operand is the element, read when
# ABOUTME: its consumer runs (design B; audit 2, K5, once refused by name): the deparser's round trip is perl's.
use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);
use JSON::PP ();
use lib 'lib';
use SoN::Deparse;

# THE DEFECT (second final audit, class K5): `($a[0] = 5) + ($a[0] = 7)` is
# 14 in perl -- each operand is the element, read when the add runs -- and
# the graph added the two values, 12. It was refused by name; design B reads
# every SV operand at its consumer's version (FromOptree's
# _reread_alias_operand_stored_later), so it is lowered.

my $dir = tempdir( CLEANUP => 1 );
my $n   = 0;
sub put ($src) { my $f = "$dir/p" . ++$n . '.pl'; open my $o, '>', $f or die $!; print $o $src; close $o; return $f }
sub round_trips ($src) {
    my $want = qx($^X @{[ put($src) ]} 2>&1);
    my $j = qx($^X -Ilib -MO=-q,SoN,json @{[ put($src) ]} 2>/dev/null);
    my $data = eval { JSON::PP->new->decode($j) } or return fail "translates: $src";
    my $d = SoN::Deparse->new;
    my $out = $d->render($data) // return fail "renders: $src (" . ( $d->gap // '' ) . ')';
    is qx($^X @{[ put($out) ]} 2>&1), $want, "perl's answer: $src";
}
round_trips($_) for
    'my @a=(1,2,3); my $n = ($a[0] += 1) + ($a[0] += 1); print "$n\n";',
    'my %h=(a=>1); my $n = ($h{a} += 1) + ($h{a} += 1); print "$n\n";',
    'my @a=(1); my $n = ($a[0] = 5) + ($a[0] = 7); print "$n\n";',
    'my @a=(1); my $n = ++$a[0] + ++$a[0]; print "$n\n";',
    'my @a=(1); my @l=(++$a[0], ++$a[0]); print "@l\n";',
    'my @a=(1); my $n = ($a[0] += 1) + 1; print "$n\n";',
    'my @a=(1); my @b=(2); my $n = ($a[0] = 5) + ($b[0] = 7); print "$n\n";';
done_testing;
