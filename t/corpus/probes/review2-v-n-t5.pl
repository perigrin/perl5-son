sub f { if ($_[0] > 1) { print "F" } else { print "G" } }
my $r = f(3); print "[", $r, "]\n";
