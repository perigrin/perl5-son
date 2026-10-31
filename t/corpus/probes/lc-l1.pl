my @p = ("ab", "c");
my $out = "";
for my $s (@p) { for my $k (1 .. 2) { $out .= length($s) } $out .= $s }
print "$out\n";
