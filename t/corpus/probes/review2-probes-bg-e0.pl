 sub f { my $n = shift; my $z = 0; if ($n > 1) { my $q = $n * 5; $z = $q } return $z } print "|", f(2), "|", f(1), "\n";
