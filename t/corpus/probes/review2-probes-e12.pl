my @a = (1,2); sub f { my $n = shift; if ($n) { push @a, 3 } return 0 } f(1); print scalar(@a), "\n";
