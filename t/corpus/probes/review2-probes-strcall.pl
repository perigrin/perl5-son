sub f { my $s = shift; my $o = ""; foreach my $c (1, 2) { $o = $o . $s } return $o } print f("ab"), "\n";
