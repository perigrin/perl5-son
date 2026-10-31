my $c = [1, [2, [3, undef]]];
my $n = 0;
while (defined $c) { $n += $c->[0]; $c = $c->[1] }
print "$n\n";
