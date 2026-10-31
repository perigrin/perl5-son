use v5.38; use experimental 'class';
sub f { my $n = shift; if ($n > 0) { print "p" } return $n + 1 }
class C { field $z = 4; method m ($k) { my $r = main::f($k); return $r + $z } }
print C->new->m(2), "\n";
