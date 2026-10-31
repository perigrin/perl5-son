my $s=''; for my $i (1..6) { $s .= $i; if ($i == 2) { $s .= "a"; next } if ($i == 4) { $s .= "b"; next } $s .= "-" } print "$s\n";
