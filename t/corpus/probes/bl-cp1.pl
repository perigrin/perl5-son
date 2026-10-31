my $k = 1; my $f = sub { $k * 10 }; my $a = $f->(); $k = 2; my $b = $f->(); print "$a $b\n";
