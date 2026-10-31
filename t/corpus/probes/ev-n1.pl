sub g { my $r = eval { die "inner\n" if $_[0]; 5 }; return defined $r ? "g=$r" : "g caught" }
my $o = eval { print g(1), "\n"; 9 };
print defined $o ? "outer ran $o [$@]\n" : "outer died: $@";
