my $s = ""; for my $i (1 .. 3) { for my $j (1 .. 3) { $s .= "$i$j "; if ($j == 2) { last } else { next } } } print "$s\n";
