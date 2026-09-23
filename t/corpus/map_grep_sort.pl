# ListAppend (the map/grep accumulator), NumCmp in a sort comparator
my @n = (3, 1, 2);
my @doubled = map { $_ * 2 } @n;
print "@doubled\n";
my @big = grep { $_ > 1 } @n;
print "@big\n";
my @sorted = sort { $a <=> $b } @n;
print "@sorted\n";
my @pairs = map { ($_, $_) } (1, 2);
print scalar(@pairs), "\n";
