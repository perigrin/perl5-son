my @a = (1,2);
sub f { my $n = shift; $a[0] = $n; return 0 }
f(5);
print "$a[0]\n";
