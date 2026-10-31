sub f { my @o; for my $x (@_) { push @o, $x if $x ne "b"; push @o, "!" if $x eq "c" } "@o" } print f(qw(a b c)), "\n";
