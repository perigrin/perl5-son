sub f { my $n = shift; if ($n) { print "x" } return } my @r = f(1); print scalar(@r), "\n";
