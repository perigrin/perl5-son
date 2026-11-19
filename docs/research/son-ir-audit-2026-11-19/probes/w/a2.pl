my @a = (1,2,3);
my $c = @ARGV;
if ($c) { $a[0] = 10 } else { $a[1] = 20 }
print "$a[0] $a[1]\n";
