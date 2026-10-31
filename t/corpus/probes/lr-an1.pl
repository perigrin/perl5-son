sub f { my ($c, $a, $b) = @_; if ($c) { if ($a && $b) { return "y$b" } } return "n" } my @x = (1, "P", 3); my @y = (1, "P", 0); print f(@x), f(@y), "\n";
