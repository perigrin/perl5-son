sub f { my $n = shift; if ($n) { die "boom\n" } return 1 } f(0); print "ok\n";
