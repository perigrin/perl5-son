sub f { my %h = (a => 1); my @a; push @a, 1, 2; my $s = ""; for my $x (@a) { $h{a} = 9; $s .= $x } print "$s|$h{a}\n" } f();
