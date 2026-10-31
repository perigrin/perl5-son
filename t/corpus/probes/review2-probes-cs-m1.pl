use v5.38; use experimental 'class';
my $k = 3;
sub f { my $n = shift; if ($n > 0) { print "p" } return $k + $n }
class C { method m ($k) { return main::f($k * 10) } }
print C->new->m(2), "\n";
