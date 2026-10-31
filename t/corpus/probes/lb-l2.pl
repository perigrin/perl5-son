my $s = ""; O: for my $i (1 .. 3) { for my $j (1 .. 3) { next O if $j == 2; $s .= "$i$j " } } print "$s\n";
