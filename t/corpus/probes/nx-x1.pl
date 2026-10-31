my $s = "";
for my $i (1 .. 4) {
    next if $i == 2;
    $s .= $i;
}
print "$s\n";
