sub h { print "h"; return 2 }
sub f { my $v = h(); if ($v > 1) { print "b" } return $v + h() }
print f(), "\n";
