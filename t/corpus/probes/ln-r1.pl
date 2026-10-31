sub c { my ($n) = @_; return () unless defined $n; my @c = (1) x $n; return @c } my @a = c(2); my @b = c(undef); print scalar(@a), scalar(@b), "\n";
