my $s = "";
for my $i (1 .. 3) { for my $j (1 .. 4) { next if $j == 2; next if $j == 3 && $i == 2; $s .= "$i$j " } }
print "$s\n";
