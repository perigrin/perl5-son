sub f { my ($s, @r) = @_; my @o; for my $x (@r) { next if $x eq $s; push @o, $x } "@o" } print f(qw(b a b c)), "\n";
