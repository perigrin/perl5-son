sub f { my $n = shift; print "f\n"; return $n + 1 }
sub g { my $m = shift; return $m * 2 }
print g(3), "\n";
print f(3), "\n";
