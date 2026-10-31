sub f { my $s = ""; for my $i (0 .. $#_) { $s = $s . $_[$i] } return $s } print f("a", "b"), "\n";
