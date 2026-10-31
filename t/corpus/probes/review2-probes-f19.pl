sub f { my ($a, $b) = @_; if ($a > $b) { return $a } return $b } print f(1, 2), f(5, 3), "\n";
