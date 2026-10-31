my $s=''; O: for my $i (1..3) { for my $j (1..3) { $s .= "$i$j "; if ($j == 2) { last O } else { next } } } print "$s\n";
