sub f { my $n = shift; if ($n > 1) { print "a"; 4 } else { print "c"; 6 } }
print "[", f(2), f(0), "]\n";
