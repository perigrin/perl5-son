sub items { my $r = shift; return $r->@* }
my @got = items([1, 2, 3]);
my $count = items([4, 5]);
print scalar(@got), " ", $count, "\n";
