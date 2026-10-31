sub g { my $n = shift; if ($n > 1) { print "G" } return $n }
sub f { my $n = shift; foreach my $i (1 .. $n) { print g($i) } return 0 }
f(3); print "\n";
