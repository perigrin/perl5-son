sub f { my ($c, $a, $b) = @_; my @l = (1); if ($c) { if ($a && $b) { my @x = (5); @l = @x } } push @l, 9; return "@l" } print f(1, 1, 1), "|", f(1, 0, 1), "|", f(0, 1, 1), "\n";
