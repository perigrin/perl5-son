sub two { (1, 2) }
sub go { my ($a, $b, $c) = two(); print "$a $b ", $c // 'u', "\n" }
go();
