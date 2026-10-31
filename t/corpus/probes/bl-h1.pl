print STDERR "e\n"; print STDOUT "o\n"; open(my $fh, "<", \"a\nb\n"); my @l = <$fh>; my $e = eof($fh); my $x = <$fh>; print scalar(@l), defined($x) ? "d":"u", "\n";
