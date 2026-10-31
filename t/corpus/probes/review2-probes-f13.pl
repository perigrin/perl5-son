sub f { my $n = shift; my %h; if ($n) { $h{a} = 1 } return exists $h{a} ? 1 : 0 } print f(1), f(0), "\n";
