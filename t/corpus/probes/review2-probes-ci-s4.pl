sub f { my $n = shift; if ($_[0]) { print "has\n" } return $n }
print f(1, 2), "\n";
