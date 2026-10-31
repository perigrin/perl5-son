my $s = $ENV{X} // "hello world";
my $tail = substr($s, 6);
my $mid = substr($s, 3, 2);
my $neg = substr($s, -5, 3);
print "[$tail][$mid][$neg]\n";
