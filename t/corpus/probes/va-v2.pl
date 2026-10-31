sub f { my @o; for (my $i = 0; $i < @_; $i++) { next if $_[$i] eq "b"; push @o, $_[$i] } return join ",", @o } print f(qw(a b c)), "\n";
