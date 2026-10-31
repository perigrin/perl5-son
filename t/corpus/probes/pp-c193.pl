sub g { $_[0] = $_[0] * 10 }
sub f { my @n = (1, 2); g($_) for @n; return "@n" }
print f(), "\n";
