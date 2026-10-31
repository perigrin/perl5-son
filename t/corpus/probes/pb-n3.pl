my $o = ""; for my $p (0 .. 5) { if ($p > 1) { if ($p == 3) { $o .= "<"; next } } $o .= $p } print "$o\n";
