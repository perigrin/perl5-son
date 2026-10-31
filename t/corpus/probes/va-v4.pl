sub f { my @o; for (my $i = 0; $i < @_; $i++) { push @o, $_[$i] } return join ",", @o } print f(qw(a b c)), "\n";
