sub f { my ($n) = @_; return "neg" if $n < 0; return "zero" unless $n; "pos" } print join(",", map { f($_) } -1, 0, 5), "\n";
