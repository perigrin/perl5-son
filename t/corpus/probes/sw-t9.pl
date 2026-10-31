my @o = (0); for my $x (qw(a b c)) { if ($x eq "b") { $o[0] += 10 } else { $o[0] += 1 } } print $o[0], "\n";
