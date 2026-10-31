my $t = 0; my $add = sub { $t += $_[0] }; for my $x (1 .. 4) { $add->($x) if $x != 3 } print "$t\n";
