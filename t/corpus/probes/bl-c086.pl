my %h = (a => 1);
my @a = (2);
my $x = sprintf("%s %d", $h{a}, $a[0]);
$h{a} = 5;
$a[0] = 6;
print "$x $h{a} $a[0]\n";
