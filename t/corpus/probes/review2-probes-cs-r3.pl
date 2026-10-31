sub f { return $_[0] + 1 }
sub g { my $n = shift; return $n * 2 }
print f(1), " ", g(5), "\n";
