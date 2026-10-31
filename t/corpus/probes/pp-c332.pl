my @a = ($ENV{X} // 1, 2, 3);
my @b = ($ENV{X} // 1, 2, 3);
undef @a;
@b = undef;
print scalar @a, scalar @b, "\n";
