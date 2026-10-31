my @dead; for my $k (qw(a b c)) { push @dead, $k unless $k eq "b" } my @got; for my $d (@dead) { push @got, uc $d } print "@got\n";
