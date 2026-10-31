sub f { my $s = ""; for my $i (1 .. 9) { last if $i > $_[1]; return "r$s" if $i == $_[0]; $s .= $i } return "e$s" }
print f(3, 9), " ", f(7, 4), "\n";
