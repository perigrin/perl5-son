my $s = ""; O: for my $i (1 .. 3) { for my $j (1 .. 3) { $s .= "$i$j "; last O if $j == 2 } } print "$s\n";
