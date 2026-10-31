open(my $fh, "<", \"x\ny\n"); my $first = <$fh>; my @rest = <$fh>; print $first, scalar(@rest), eof($fh) ? " eof" : "", "\n";
