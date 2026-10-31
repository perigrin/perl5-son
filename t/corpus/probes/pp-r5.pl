sub f { if ($_[0]) { if ($_[0] > 1) { return "a" } else { return "b" } } else { return "c" } }
print f(2), f(1), f(0), "\n";
sub g { my $x = shift; if ($x > 1) { if ($x > 2) { print "p\n"; return 3 } return 2 } return 1 }
print g(3), g(2), g(0), "\n";
