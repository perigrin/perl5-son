our ($x, $y) = (1, 2); { no strict 'refs'; for my $n ("x", "y") { local ${$n} = 9; print "$x$y;" } } print "$x$y\n";
