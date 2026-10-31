my @a; sub add { my $n = shift; if ($n) { push @a, $n } return 0 } add(1); add(2); print "@a\n";
