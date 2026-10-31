sub f { my @l = (7, 8); if ($_[0] > 1) { print "F" } return $l[1] + $_[0] }
sub g { my @l = (5, 6); if ($_[0] > 1) { print "G" } return $l[0] + $_[0] }
print f(1), " ", g(3), "\n";
