sub f { my @p = (1); my $add = sub { push @p, $_[0] + 1 if $_[0] < 4 }; my $out = ""; for my $x (@p) { $add->($x); $out .= $x } return $out }
print f(), "\n";
