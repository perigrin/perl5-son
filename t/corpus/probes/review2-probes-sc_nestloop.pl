sub f { my $n = shift; for my $i (1..$n) { for my $j (1..$i) { print $j } print "|" } return 0 } f(3); print "\n";
