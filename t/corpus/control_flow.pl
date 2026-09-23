# If, Proj, Region, Phi, Loop, Not, NumEq..NumNe, NumCmp, PadAccess
my $n = 0;
my $total = 0;
while ($n < 5) {
    if ($n == 2)      { $total += 100 }
    elsif ($n != 3)   { $total += $n }
    $n++;
}
print "$total\n";
print(!0 ? "t" : "f", "\n");
my @vals = (5, 2, 9);
my $cmp = $vals[0] <=> $vals[1];
print "$cmp\n";
for (my $i = 0; $i <= 2; $i++) { print "i$i " }
print "\n";
print(($vals[0] <  $vals[1]) ? 1 : 0, "\n");
print(($vals[0] <= $vals[1]) ? 1 : 0, "\n");
print(($vals[0] >  $vals[1]) ? 1 : 0, "\n");
print(($vals[0] >= $vals[1]) ? 1 : 0, "\n");
