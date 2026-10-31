sub h { print "H"; return 1 }
sub g { my @l = (5, 6); if ($_[0] > 0) { print "P" } return $l[h()] + $_[0] }
print g(1), "\n";
