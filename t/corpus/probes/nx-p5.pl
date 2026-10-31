my $s = "";
for my $i (1 .. 9) { next if $i == 2; $s .= $i; next if $i == 4; last if $i == 6; $s .= "-" }
print "$s\n";
