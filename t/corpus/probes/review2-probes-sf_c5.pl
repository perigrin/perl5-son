sub f { my $n = shift; if ($n > 1) { print "F" } return 0 } my @a = (5); my $x = shift(@a) + 1; f(1); print "$x\n";
