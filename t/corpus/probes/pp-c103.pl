use v5.36; my sub a ($x) { $x + 1 } my sub b ($x) { a($x) * 2 } my $r = \&b; print b(1), " ", $r->(2), "\n";
