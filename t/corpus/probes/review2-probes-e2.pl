my $x = 1; sub f { my $n = shift; if ($n) { $x = 7 } return 0 } f(1); print $x, "\n";
