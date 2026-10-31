sub f { my $n = shift; if ($_[0]) { print "x\n" } return 1 }
sub g { my @a = (4, 5); f(1); return $a[1] }
print g(), "\n";
