sub f { my @o; for my $x (@_) { next if $x eq "b"; push @o, $x; push @o, $x } scalar @o } print f(qw(a b c)), "\n";
