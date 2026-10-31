my @in = qw(a b c); my @o; for my $x (@in) { next if $x eq "b"; push @o, $x } print "@o\n";
