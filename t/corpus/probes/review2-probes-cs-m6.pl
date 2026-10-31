sub f { my $n = shift; my $s = 0; foreach my $i (1 .. $n) { $s = $s + $i } return $s }
print f(3), " ", f(4), "\n";
