my $i = 0; sub f { my $n = shift; my $k = 0; while ($k < $n) { $k++ } return $k } while ($i < 2) { print f($i + 1); $i++ } print "\n";
