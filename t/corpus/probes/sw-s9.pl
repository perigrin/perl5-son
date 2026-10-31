sub g { $_[0] . "!" } sub f { my @o; for my $x (@_) { next if $x eq "b"; push @o, g($x) } "@o" } print f(qw(a b c)), "\n";
