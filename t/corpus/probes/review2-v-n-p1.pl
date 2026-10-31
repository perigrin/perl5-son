sub f { if ($_[0] > 1) { print "x" } else { 5 } }
my $a = f(3); my $b = f(0); print "[", $a, "][", $b, "]\n";
