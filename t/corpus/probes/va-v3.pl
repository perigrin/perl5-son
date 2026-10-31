sub f { my @o; my $i = 0; while ($i < @_) { if ($_[$i] eq "b") { $i += 2; next } push @o, $_[$i]; $i++ } return "@o" } print f(qw(a b x c)), "\n";
