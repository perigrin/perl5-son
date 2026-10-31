sub f { my $n = shift; my $o = ""; for my $i (1 .. $n) { next if $i == 2; $o = $o . $i } return $o } print f(4), "\n";
