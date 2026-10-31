sub f { my $n = shift; my $y = $n; if ($n) { $y = 9 } return $y } print defined(f(1)) ? "d" : "u", "\n";
