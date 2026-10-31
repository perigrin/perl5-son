my $x = 5; { local $_ = 3; $x += $_ } print "$x\n";
