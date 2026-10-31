my $t = 0; my $add = sub { $t += $_[0] }; $add->(3); $add->(4); print "$t\n";
