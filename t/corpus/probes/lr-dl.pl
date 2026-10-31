sub k { my $r = shift; if ($r eq 'a') { return "A$r" } elsif ($r eq 'b') { return "B$r" } else { die "no $r\n" } }
my $x = k('a'); my $y = k('b'); my @z = k('a');
print "$x $y ", scalar(@z), "\n";
