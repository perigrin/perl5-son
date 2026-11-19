my @a=(0); my $n=0;
for my $i1 (1..2) { for my $i2 (1..2) { $n++; $a[0] += $n; }}
print "$n $a[0]\n";
