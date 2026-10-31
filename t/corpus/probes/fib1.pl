use v5.36; sub fib ($n) { return $n < 2 ? $n : fib($n - 1) + fib($n - 2) } print fib(10), "\n";
