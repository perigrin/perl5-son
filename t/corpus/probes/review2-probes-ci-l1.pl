sub f { my $n = shift; if ($n > 1) { print "big\n" } else { print "small\n" } return 0 }
my $s = 0;
foreach my $i (1..3) { f($i); $s = $s + $i }
print "$s\n";
