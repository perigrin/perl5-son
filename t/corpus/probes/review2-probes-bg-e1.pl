 my $v1 = shift(@ARGV) // 1; $v1 = $v1 + 1; print $v1; sub f { my $n = shift; my $z = 0; if ($n > 1) { my $q = $n * 5; $z = $q } return $z } print "|", f(2), "|", f(1), "\n";
