sub f { my $n = shift; print "x\n"; return 0 }
my $s = 0;
foreach my $i (1..3) { f($i); $s = $s + $i }
print "$s\n";
