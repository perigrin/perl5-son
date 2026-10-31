use v5.38; use experimental 'class';
my $k;
sub f { my $n = shift; if ($n > 0) { print "p" } return defined($k) ? "def" : "undef" }
class C { method m ($k) { return main::f($k) } }
print C->new->m(2), "\n";
