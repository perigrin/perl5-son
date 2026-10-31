sub f { my $n = shift; foreach my $k (1..$n) { print $k } print "\n"; return 0 }
my $c = 1;
if ($c) { f(2) } else { f(3) }
print "done\n";
