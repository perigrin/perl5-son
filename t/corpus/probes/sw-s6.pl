sub f { my $n = 0; for my $x (@_) { for my $y (1 .. 2) { next if $y == 2; $n += $x * $y } } $n } print f(1, 2, 3), "\n";
