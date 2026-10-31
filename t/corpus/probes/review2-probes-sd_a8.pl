sub f { my $n = shift; foreach my $i (1..$n) { if ($i % 2) { print "o" } print "." } return 0 } f(3); print "\n";
