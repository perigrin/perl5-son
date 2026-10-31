my @p = qw(a %x b); my @o; for (my $i = 0; $i < @p; $i += 2) { my $k = $p[$i]; if ($k =~ /^%/) { push @o, "s"; $i--; next } push @o, "$k=" . $p[$i + 1] } print "@o\n";
