sub g { my $x = shift; return $x * 2 }
sub f { my $y = shift; return g($y + 1) }
print f(3), "\n";
