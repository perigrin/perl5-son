sub f { my @o; for my $x (@_) { next if $x eq "b"; my $y = $x x 2; push @o, $y } "@o" } print f(qw(a b c)), "\n";
