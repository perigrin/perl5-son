my $n = 0;
for my $k (1 .. 3) { my $r = eval { die "k$k\n" if $k == 2; $k }; print defined $r ? "r$r\n" : "caught $@"; }
