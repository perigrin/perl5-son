sub f { my @o; for my $x (@_) { next if $x eq "b"; push @o, $x } return scalar(@o) } print f(qw(a b c)), "\n";
