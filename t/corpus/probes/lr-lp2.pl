my $s = $ENV{N_UNSET_FOR_TEST} // "1"; my $k = 0; while ($k < 3) { $s = $s * 2; $k++ } print "$s\n";
