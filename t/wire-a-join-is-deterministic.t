# ABOUTME: The IR is the same on every run: a join where several variables differ makes
# ABOUTME: its Phis in one order, whatever perl's hash seed is.

use v5.42.0;
use Test2::V0;
use File::Temp qw(tempdir);

my $dir = tempdir(CLEANUP => 1);

sub produce_with_seed ($src, $seed) {
    my $f = "$dir/p.pl";
    open my $fh, '>', $f or die $!; print $fh $src; close $fh;
    local $ENV{PERL_HASH_SEED} = $seed;
    local $ENV{PERL_PERTURB_KEYS} = 1;
    return scalar qx($^X -Ilib -MO=-q,SoN,json $f 2>/dev/null);
}

# Each program has a join where two or more variables differ between the arms.
for my $src (
    'my $s = 0; my $o = ""; for my $i (1..4) { if ($i > 1) { my $k = 0; while ($k < $i) { $s += $k; $k++ } $o .= $s } } print "$o $s\n";',
    'my ($a, $b, $c) = (1, 2, 3); if ($ARGV[0]) { $a = 4; $b = 5; $c = 6 } print "$a $b $c\n";',
    'my ($a, $b, $c, $d) = (1, 2, 3, 4); for my $i (1..2) { $a++; $b += $i; $c .= $i; $d = $i } print "$a $b $c $d\n";',
) {
    my %seen;
    $seen{ produce_with_seed($src, $_) }++ for 1 .. 8;
    is scalar(keys %seen), 1, "one IR under eight hash seeds: $src";
}

done_testing;
