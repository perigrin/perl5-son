my $p = 0; my $o = ""; while ($p < 6) { if ($p == 2) { for my $k (1 .. 2) { $o .= "<$k>" } $p += 2; next } $o .= $p; $p++ } print "$o\n";
