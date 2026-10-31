sub f { if ($_[0]) { print "x\n" } return 1 }
sub g { my @a = (4, 5); my $r = f(1); return $a[1] + $r }
print g(), "\n";
