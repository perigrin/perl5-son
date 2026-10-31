my @a = (1,2,3); sub f { my $n = shift; $a[0] = $n; return 0 } f(9); print "@a\n";
