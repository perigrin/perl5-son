sub f { my ($c, $a, $b) = @_; return "$c/$a/" . ($b // 'u') } print f(1, "P"), "\n";
