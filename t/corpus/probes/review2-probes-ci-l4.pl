sub f { my $n = shift; if ($n) { print "t\n" } return 1 }
my $y = f(1) ? f(0) : 5;
print "$y\n";
