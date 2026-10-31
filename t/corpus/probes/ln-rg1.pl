my $n = @ARGV + 3; my @m = map { $_ * 2 } 1 .. $n; print "@m\n"; my @g = grep { $_ % 2 } 2 .. $n + 2; print "@g\n";
