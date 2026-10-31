use v5.38;
my $k = 3;
sub f { my $n = shift; if ($n > 0) { print "p" } return $k + $n }
print f(1), "\n";
