sub twice { return $_[0] * 2 }
my @r;
for my $n (1 .. 3) { push @r, twice($n) }
print "@r\n";
