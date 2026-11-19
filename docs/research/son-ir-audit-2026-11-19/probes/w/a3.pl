my @a = (1,2,3);
my $i = 0;
while ($i < 3) { $a[$i] = $a[$i] * 2; $i++ }
print "$a[0] $a[1] $a[2]\n";
