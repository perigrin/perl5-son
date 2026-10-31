sub shout { return uc $_[0] }
my @loud = map { shout($_) } qw(a b c);
print "@loud\n";
