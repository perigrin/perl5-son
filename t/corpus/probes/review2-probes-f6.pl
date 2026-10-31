sub f { my $n = shift; foreach my $i (1..$n) { if ($i == 2) { last } print $i } return 0 } f(4); print "\n";
