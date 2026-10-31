my $x = 5; my $r = eval { $x * 2 }; my $s = eval { die "z\n" } // "u"; print "$r $s\n";
