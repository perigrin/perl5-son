package O { sub m { $_[1] = uc $_[1] if $_[1] eq "b" } }
my @n = sort qw(c b a); for my $x (@n) { O->m($x) } print "@n\n";
