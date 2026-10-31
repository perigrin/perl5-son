my $s = "";
for my $i (1 .. 6) {
    next if $i == 2;
    next if $i == 4;
    $s .= $i;
}
print "$s\n";
