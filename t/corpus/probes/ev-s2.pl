my @a = (1, 2);
my $r = eval { my $p = \$a[-5]; 1 };
print defined $r ? "ran\n" : "died\n";
