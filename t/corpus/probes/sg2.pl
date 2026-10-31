use v5.42;
sub f { my $mk = sub ($id, @rest) { return scalar @rest }; return $mk->(4) . $mk->(1,2) }
print f(), "\n";
