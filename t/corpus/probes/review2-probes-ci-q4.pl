sub f { if ($_[0] > 2) { print "big\n" } return $_[0] }
sub g { my $v = f(1); return $v + $_[0] }
print g(5), "\n";
