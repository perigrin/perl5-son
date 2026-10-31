our $g = 1; sub f { $g = 7 } my $before = $g; f(); print "$before $g\n";
