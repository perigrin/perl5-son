my $x = 5;
sub f { my $y = 7; if ($_[0]) { print "a" } return $y + $x }
print f(1), "\n";
