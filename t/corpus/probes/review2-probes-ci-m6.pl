sub f { my $n = shift; my $y = 1; if ($n) { $y = 9 } return $y + 0 }
print f(1) + f(0), "\n";
