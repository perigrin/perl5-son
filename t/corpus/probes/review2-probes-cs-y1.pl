sub f { if ($_[0] > 1) { print "F" } return $_[0] + 1 }
sub g { my @l = (5, 6); if ($_[0] > 1) { print "G" } return $l[0] + $_[0] }
print f(1), " ", f(3), " ", g(2), "\n";
