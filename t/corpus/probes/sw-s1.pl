sub f { my @o; for my $x (@_) { last if $x eq "c"; push @o, $x } join ",", @o } print f(qw(a b c d)), "\n";
