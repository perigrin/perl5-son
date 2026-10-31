my @p = qw(a x b c); my @o; for (my $i = 0; $i < 4; $i += 2) { if ($p[$i] eq "x") { push @o, "s"; $i--; next } push @o, $p[$i + 1] } print "@o\n";
