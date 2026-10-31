sub safe { my $r = eval { die "no\n" if $_[0] > 1; $_[0] * 10 }; defined $r ? $r : -1 }
print safe(1), " ", safe(2), "\n";
