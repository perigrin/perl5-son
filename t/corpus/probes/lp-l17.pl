sub f { my $n = shift; my $o = ""; for my $i (1 .. $n) { if ($i == 2) { $o = $o . "x"; next } $o = $o . $i } return $o } print f(3), "\n";
