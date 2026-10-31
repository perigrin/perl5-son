my $o = ""; for my $p (0 .. 3) { if ($p == 2) { for my $k (1 .. 2) { $o .= "<$k>" } next } $o .= $p } print "$o\n";
