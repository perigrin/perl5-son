sub h { print "H"; return 1 }
sub f { my @l = (7, 8); if ($_[0] > 1) { print "F" } return $l[1] + $_[0] }
sub g { my @l = (5, 6); return $l[h()] + $_[0] }
print f(3), "\n"; print g(1), "\n";
