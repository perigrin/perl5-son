my ($n, $t) = (0, 0);
while ($n < 10) { $n++; next if $n % 3 == 0; next if $n == 5; $t += $n }
print "$t $n\n";
