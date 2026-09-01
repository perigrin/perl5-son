sub lit { return (10,20,30) }
sub agg { my @a=(10,20,30); return @a }
sub mix { my @x=(10,20); return (99,@x) }
my $s = lit();
my @l = lit();
mix();
print "$s @l";
