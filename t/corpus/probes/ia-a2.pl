sub f { my ($a) = @_; my @c; if ($a > 0) { push @c, $a; return "early @c" if $a > 5 } push @c, 0; return "late @c" }
print f(9), "|", f(2), "|", f(-1), "\n";
