my $x = $ENV{NO_SUCH_VAR} // [1];
my $r = eval { my $v = $$x; 1 };
print defined $r ? "ran\n" : "died\n";
