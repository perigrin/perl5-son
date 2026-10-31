sub f { my $n = shift; if ($n > 1) { print "a" } elsif ($n > 0) { print "b" } else { print "c" } }
print "[", f(2), f(1), f(0), "]\n";
