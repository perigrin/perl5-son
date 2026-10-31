sub f { my ($c, @n) = @_; my @l = (1); if ($c) { my @x; push @x, @n; @l = @x } push @l, "}"; return "@l" } print f(1, 2, 3), "|", f(0, 2), "\n";
