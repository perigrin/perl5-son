sub f { my @o; for my $x (@_) { next if !defined $x; push @o, $x } "@o" } print f("a", undef, "c"), "\n";
