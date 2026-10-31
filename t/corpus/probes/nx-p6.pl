my @a = (3, 0, 7, 0, 2); my $c = 0; my $sum = 0;
foreach my $x (@a) { next unless $x; $c++; next if $x > 5; $sum += $x }
print "$c $sum\n";
