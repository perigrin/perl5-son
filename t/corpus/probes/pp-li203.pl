sub k { return \$_[0] } sub g { (1, 2, 3) }
sub f { my @a = g(); my $r; for my $x (@a) { $r = k($x) } $$r = 5;
  my @b = grep { $_ > 1 } g(); my $q; for my $x (@b) { ($q) = k($x) } $$q = 7; return "@a|@b" }
print f(), "\n";
