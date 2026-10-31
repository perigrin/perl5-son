sub f { my $n = shift; if ($n) { print "a\n" } else { print "b\n" } return 1 }
my $c = 1;
my $x = 0;
if ($c) { $x = f(1) } else { $x = 7 }
print "$x\n";
