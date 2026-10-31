sub f { if ($_[0] > 1) { print "F" } else { print "G" } }
print f(3) ? "t" : "f", "\n";
