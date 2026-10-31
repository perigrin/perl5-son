my $h = { list => [1, 2] }; push @{ $h->{list} }, 3; print scalar(@{ $h->{list} }), "\n";
