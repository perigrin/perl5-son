my $x = 5; sub f { my $x = shift; $x = $x + 1; return $x } print f(1), " $x\n";
