sub f { my @in = @_; my @o; for (my $i = 0; $i < @in; $i++) { push @o, $in[$i] } return join ",", @o } print f(qw(a b c)), "\n";
