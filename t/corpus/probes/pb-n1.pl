my $p = 0; my $o = ""; while ($p < 6) { if ($p == 2) { if ($o ne "") { $o .= "<"; $p += 2; next } } $o .= $p; $p++ } print "$o\n";
