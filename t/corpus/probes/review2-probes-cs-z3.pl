sub h { print "H"; return 1 }
sub g { my @l = (5, 6); return $l[h()] + $_[0] }
print g(1), "\n";
