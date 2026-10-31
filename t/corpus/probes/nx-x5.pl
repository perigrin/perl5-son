my $s=''; for my $i (1..5) { next if $i == 1; $s .= $i; last if $i == 3; next } print "$s\n";
