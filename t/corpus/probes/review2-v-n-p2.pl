sub f { if ($_[0] > 1) { print "x" } else { print "y" } }
my $a = f(3) + f(0); print "[", $a, "]\n";
