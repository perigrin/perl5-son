sub two { (1, 2) }
sub go { my ($a, $b, $c) = (two(), 5); print "$a $b $c\n" }
go();
