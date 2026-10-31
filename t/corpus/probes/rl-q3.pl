sub f { for my $i (1 .. 5) { return $i * 10 if $i == $_[0] } return -1 }
print f(2) + f(4), " ", f(9), "\n";
