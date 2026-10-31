sub f { my $n = shift; if ($n) { print "x"; return 1 } print "y"; return 2 } my $c = f(0) + f(1); print "$c\n";
