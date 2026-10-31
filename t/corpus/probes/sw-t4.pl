sub f { my @o = (0); for my $x (@_) { next if $x eq "b"; $o[0] = $o[0] + 1 } $o[0] } print f(qw(a b c)), "\n";
