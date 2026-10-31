sub f { my $n = shift; if ($n > 1) { print "big\n" } return $n }
my $s = 0;
foreach my $i (1..3) { $s = $s + f($i) }
print "$s\n";
