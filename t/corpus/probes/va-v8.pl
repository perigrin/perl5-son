sub f { my @o; my $i = 0; while ($i < 3) { push @o, $i; $i++ } return join ",", @o } print f(), "\n";
