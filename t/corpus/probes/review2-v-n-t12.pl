sub f { my $x = 10; my $y = $_[0]; if ($y) { print "y" } return $x + $y }
my $x = 1; my $z = 100; print f(5), $x, $z, "\n";
