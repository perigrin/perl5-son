my $i = eval { my $j = eval { die "x\n"; 1 }; print defined $j ? "j\n" : "inner caught $@"; 2 };
print "i=$i [$@]\n";
