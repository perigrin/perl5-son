sub w { my ($a, $b) = @_; return $a && $b } print w(1, 2), "|", w("x", "y"), "|", w(1.5, 2.5), "|", w("", "z"), "\n";
