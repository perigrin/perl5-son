sub f { my $c = 0; for (@_) { $c++ } return $c } print f(4, 4), "\n";
