sub f { my @o; for my $x (@_) { if ($x eq "b") { push @o, "B"; next } push @o, $x } return join ",", @o } print f(qw(a b c)), "\n";
