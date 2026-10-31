my $x = 5;
sub f { my $y = $_[0]; foreach my $i (1, 2) { $y = $y + $i } return $y }
print f(1), " ", $x, "\n";
