sub f { if (1) { print "once\n" } return 3 }
my $a = f();
my $b = f();
print $a + $b, "\n";
