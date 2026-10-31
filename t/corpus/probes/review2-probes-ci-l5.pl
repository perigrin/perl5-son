sub f { my $n = shift; if ($n) { print "t\n" } return 1 }
my $x = 0;
my $y = $x && f(1);
print "[$y]\n";
