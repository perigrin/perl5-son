my $x = 5;
sub f { my $y = 7; if ($_[0]) { $y = 9 } return $y + 3 }
print f(1), " ", f(0), " ", $x, "\n";
