my $s = "";
for my $i (1 .. 6) { if ($i > 1) { if ($i % 2) { $s .= "o"; next } $s .= "e" } next if $i == 4; $s .= $i }
print "$s\n";
