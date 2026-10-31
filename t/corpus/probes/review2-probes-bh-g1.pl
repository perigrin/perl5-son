 my $v1 = 0; foreach my $i1 (1, 2) { $v1 = $v1 + $i1 } print $v1; sub f { my $n = shift; my $z = 0; if ($n > 1) { $z = $n * 5 } print $z; return 0 } f(2); f(1); print "\n";
