sub f { my $n = shift; if ($n > 1) { print "b" } return $n }  my $v1 = 0; foreach my $i1 (1, 2) { $v1 = $v1 + $i1 } print $v1; print "|", f(3), "|", f(1), "\n";
