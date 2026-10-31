sub pair { my ($n) = @_; return unless $n; return ($n, $n + 1) } my @p = pair(0); my $s = pair(3); my @q = pair(3); print scalar(@p), " $s ", scalar(@q), "\n";
