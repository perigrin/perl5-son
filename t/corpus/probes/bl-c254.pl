my $a = $ARGV[0] // 1;
my $b = $ARGV[1] // 0;
my $and = ($a && $b);
my $or = ($a || $b);
my $dor = ($b // $a);
my $not = (not $a);
my $xor = ($a xor $b);
print "and [$and] or [$or] dor [$dor] not [$not] xor [$xor]\n";
