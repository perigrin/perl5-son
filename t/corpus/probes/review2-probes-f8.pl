sub f { my $n = shift; if ($n) { return "a" } return "b" } my $c = 1; if ($c) { print f(1) } else { print f(0) } print "\n";
