sub f { my $n = shift; if ($n) { print "x" } return 0 } my $v = f(1) || 7; print "$v\n";
