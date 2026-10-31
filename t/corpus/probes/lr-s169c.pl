sub esc { return (ord($_[0][$_[1]]) + 100, 1) }
sub f { my @chars = split //, $_[0]; my $j = 0; my @r;
  while ($j <= $#chars) { my $cc = $chars[$j]; my ($lo, $u);
    if ($cc eq '\\') { ($lo, $u) = esc(\@chars, $j + 1); $u += 1 } else { ($lo, $u) = (ord($cc), 1) }
    push @r, $lo; $j += $u }
  return "@r" }
print f('a\\nb'), "\n";
