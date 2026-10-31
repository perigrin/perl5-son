open(my $fh, "<", \"one\ntwo\n"); my @l = <$fh>; print scalar(@l), " $l[1]";
