open(my $fh, "<", \"a\nb\nc\n"); my $n = 0; while (my $l = <$fh>) { $n++ } print "$n\n";
