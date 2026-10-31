my @o = (0); my $i = 0; while ($i < 3) { $i++; next if $i == 2; $o[0] += 1 } print $o[0], "\n";
