use v5.38; use experimental 'class';
sub f { my $n = shift; if ($n > 0) { print "p" } return $n + 1 }
class C { method m ($k) { return main::f($k) } }
print C->new->m(2), "\n";
