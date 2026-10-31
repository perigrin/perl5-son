use v5.42;
sub f { my @seen; my $mk = sub ($id, @rest) { push @seen, "$id:@rest"; return scalar @rest }; my $n = $mk->(1, 2, 3) + $mk->(4); return "$n @seen" }
print f(), "\n";
