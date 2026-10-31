our $g = 1; sub f { my $x = shift; $g = $g + $x; return $g } print f(2), f(3), " $g\n";
