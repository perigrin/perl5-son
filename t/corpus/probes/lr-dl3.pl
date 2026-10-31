my %C;
sub k { my $r = shift; my $s = shift;
  return $C{$r} if exists $C{$r};
  if ($r eq 'a') { return "A$r" } elsif ($r eq 'b') { return "B$r" }
  elsif ($r eq 'n') { die "n\n" }
  else { if (defined $s && $s eq 'S') { die "s\n" } die "no $r\n" } }
$C{q} = 'cq';
my $x = k('a'); my $y = k('b'); my $w = k('q'); my @z = k('a');
print "$x $y $w ", scalar(@z), "\n";
