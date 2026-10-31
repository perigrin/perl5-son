my @out;
for my $i (1 .. 4) {
    next if $i == 2;
    push @out, $i;
}
print "@out\n";
