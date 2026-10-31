sub g { return (ord($_[0]) + 100, $_[1]) }
sub f { my @c = split //, $_[0]; my $j = 0; my @r;
  while ($j <= $#c) { my ($lo, $used) = g($c[$j], 1); my $k = $j + $used; push @r, $lo; $j = $k }
  return "@r" }
print f('ab'), "\n";
