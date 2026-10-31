sub g { my $m = shift; if ($m) { print "g\n" } return 1 }
sub f { my $n = shift; if ($n) { g($n) } return 2 }
print f(1), "\n";
