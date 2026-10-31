my $t = 0; sub f { my $n = shift; for my $i (1..$n) { $t = $t + $i } return 0 } f(3); print $t, "\n";
