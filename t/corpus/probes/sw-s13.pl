sub f { my @o; for my $x (@_) { if ($x eq "a") { push @o, 1 } else { push @o, 2 } } "@o" } print f(qw(a b a)), "\n";
