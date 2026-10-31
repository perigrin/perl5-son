sub esc { return (ord($_[0][$_[1]]) + 100, 1) }
sub f { my @chars = split //, $_[0]; my $j = 0; my @r;
  while ($j <= $#chars) { my $cc = $chars[$j]; my ($lo, $lo_used);
    if ($cc eq 'x') { ($lo, $lo_used) = esc(\@chars, $j + 1); $lo_used += 1 } else { ($lo, $lo_used) = (ord($cc), 1) }
    my $k = $j + $lo_used; push @r, $lo; $j = $k }
  return "@r" }
print f('axbc'), "\n";
