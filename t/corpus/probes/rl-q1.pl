sub f { for my $i (1 .. 3) { for my $j (1 .. 3) { return "$i$j" if $i * $j == $_[0] } } return "no" }
print f(6), " ", f(7), "\n";
