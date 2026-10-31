sub f { my $n = shift; my $y = 0; foreach my $i (1..$n) { $y = $y + $i } return $y }
my $t = f(3) + f(4);
print "$t\n";
