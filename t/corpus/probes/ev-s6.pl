my $z = $ENV{NO_SUCH_VAR} // 0;
my $r = eval { print 1 / $z, "\n"; 1 };
print defined $r ? "ran\n" : "died: $@";
