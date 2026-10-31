sub f { for my $x (@_) { $x = $x * 2 } return 1 } my @a = (1, 2); f(@a); print "@a\n";
