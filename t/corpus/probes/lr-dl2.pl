sub k { my $r = shift; if ($r eq 'a') { return "A$r" } elsif ($r eq 'b') { return "B$r" } else { if ($r eq 'c') { die "c\n" } die "no $r\n" } }
my $x = k('a'); my $y = k('b'); my @z = k('a');
print "$x $y ", scalar(@z), "\n";
