use v5.38; use experimental 'class';
sub f { my $n = shift; if ($n > 1) { print "p" } return $n + 1 }
class C { method m ($k) { return main::f($k) + main::f($k + 1) } }
print C->new->m(1), "\n";
