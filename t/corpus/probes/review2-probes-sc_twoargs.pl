sub f { my ($a,$b) = @_; if ($a > $b) { print "a" } else { print "b" } return $a+$b } print f(1,2), f(3,1), "\n";
