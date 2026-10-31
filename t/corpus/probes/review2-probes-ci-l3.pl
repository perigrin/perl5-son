sub f { my $n = shift; my $r = 0; if ($n > 1) { $r = 10 } return $r }
my $x = 0;
foreach my $i (1..3) { my $t = f($i); print "$t\n" }
