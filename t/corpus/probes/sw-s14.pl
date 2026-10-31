sub f { my @o; for my $x (@_) { push @o, $x eq "a" ? "A" : $x } "@o" } print f(qw(a b a)), "\n";
