my @o; for my $x (qw(a b c)) { if ($x eq "b") { push @o, "B"; next } push @o, $x } print "@o\n";
