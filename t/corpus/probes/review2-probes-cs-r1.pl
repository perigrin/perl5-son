sub f { my $n = shift; print "f$n\n"; return $n + 1 }
sub g { my $n = shift; print "g$n\n"; return $n * 2 }
print f(1) + g(5), "\n";
