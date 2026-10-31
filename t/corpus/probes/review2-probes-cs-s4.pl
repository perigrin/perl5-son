sub g { my $n = shift; return $n * 2 }
sub f { my $n = shift; if ($n > 1) { print "F" } return $n + 1 }
print f(1), " ", f(3), "\n";
