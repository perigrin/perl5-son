my %h = (k => 1); sub f { my $n = shift; $h{k} = $n; return 0 } f(4); print "$h{k}\n";
