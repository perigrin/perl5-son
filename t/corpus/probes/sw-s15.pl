sub f { my $c = 0; for my $x (@_) { $c++ if $x eq "a"; $c += 10 if $x eq "b" } $c } print f(qw(a b a)), "\n";
