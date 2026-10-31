my %c = (a => 0); for (1 .. 3) { $c{a}++ ; $c{b} //= $_ } print "$c{a} $c{b}\n";
