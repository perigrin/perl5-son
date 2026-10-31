sub f { my $n = shift; my $m = shift; if ($n) { print $m } return 1 } f(1, "a"); f(0, "b"); f(1,"c"); print "\n";
