sub f { my $n = shift; my $s = ""; if ($n) { $s = "y" } else { $s = "n" } return $s } my $a = f(1); my $b = f(0); print "$a$b\n";
