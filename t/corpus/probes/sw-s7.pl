sub f { my @o; my $i = 0; while ($i < @_) { my $x = $_[$i++]; next if $x eq "b"; push @o, $x } "@o" } print f(qw(a b c)), "\n";
