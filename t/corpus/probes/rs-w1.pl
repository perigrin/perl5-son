my @o; for my $x (qw(a1 b2 c)) { my $y = $x; $y =~ s/(\d)/<$1>/; push @o, $y } print "@o\n";
