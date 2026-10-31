sub f { for my $i (1 .. 3) { return "E$i" if $i == $_[0] } return "L" }
print f(2), f(9), "\n";
