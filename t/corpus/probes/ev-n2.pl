my $c = $ENV{NO_SUCH_VAR} // 1;
my $o = eval { if ($c) { my $i = eval { die "in arm\n"; 1 }; print defined $i ? "i\n" : "arm caught $@"; } 3 };
print defined $o ? "o=$o\n" : "outer died: $@";
