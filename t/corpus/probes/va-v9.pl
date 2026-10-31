sub f { my @o; for my $i (0 .. 2) { push @o, $i } return join ",", @o } print f(), "\n";
