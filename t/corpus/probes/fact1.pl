use v5.36; sub fact ($n) { return $n <= 1 ? 1 : $n * fact($n - 1) } print fact(5), " ", fact(1), "\n";
