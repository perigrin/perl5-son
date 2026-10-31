sub g { my $m = shift; return $m * 2 }
sub f { my $n = shift; print "f $n\n"; return 0 }
f(1);
print g(3), "\n";
