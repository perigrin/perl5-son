sub f { my $x = $_[0]; if ($x > 1) { print "F" } return $x * 2 }
print f(1), " ", f(3), "\n";
