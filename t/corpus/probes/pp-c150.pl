use v5.42;
my @a = (1, 2);
my $g = sub ($x, $y) { $x + $y };
my @r;
for my $i (@a) { my $v = $g->($i, 1); push @r, $v }
print "@a @r\n";
