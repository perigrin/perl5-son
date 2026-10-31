sub bump { $_[0]++ }
my @a = (1, 2);
for my $x (@a) { bump($x) }
print "@a\n";
