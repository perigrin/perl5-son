sub f { my $n = shift; for my $i (1..$n) { last if $i > 2; print $i } return 0 } f(5); print "\n";
