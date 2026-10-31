sub f { my $n = 0; for my $x (@_) { if ($x > 0) { if ($x > 100) { return "big $x" } $n += $x } } return "sum $n" }
print f(1, 2, 3), "; ", f(5, 500, 7), "\n";
