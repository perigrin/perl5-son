sub f { if ($_[0] > 1) { print "x" } else { "s" } }
print "[", f(3), "][", f(0), "]\n";
