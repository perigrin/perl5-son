my @a = (1, 2, 3);
my $c = 1;
if ($c) { foreach my $v (@a) { print $v } $a[0] = 9 }
print "$a[0]\n";
