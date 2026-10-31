my @a = (1); my @b = (); my $c = scalar(@a); my $d = scalar(@b);
my $v = $c && (2 < 1); my $w = $d && (2 < 1); my $x = $c || (2 < 1); my $y = $d || (1 < 2); my $z = $d || (2 < 1);
print "[$v][$w][$x][$y][$z]\n";
