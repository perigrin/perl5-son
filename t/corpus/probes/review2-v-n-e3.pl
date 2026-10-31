my $g = 1;
sub f { if ($_[0]) { $g = 9 } return 0 }
f(1); print $g, "\n";
