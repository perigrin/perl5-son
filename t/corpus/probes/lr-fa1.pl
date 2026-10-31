sub f { my ($c, $a, $b) = @_; return "$c/$a/" . ($b // 'u') } my @x = (1, "P", 3); print f(@x), "\n";
