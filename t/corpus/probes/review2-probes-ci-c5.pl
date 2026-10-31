sub f { my $n = shift; if ($n) { print "in\n" } return 2 }
my $x = 3;
my $y = $x + f(1);
print "$y\n";
