sub collect { my ($n) = @_; return () unless defined $n; my @c = map { "n$_" } 1 .. $n; return @c } my @a = collect(2); my @b = collect(undef); print scalar(@a), " ", scalar(@b), "\n";
