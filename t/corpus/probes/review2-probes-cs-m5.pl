use v5.38; use experimental 'class';
sub f { my $n = shift; my $s = 0; foreach my $i (1 .. $n) { $s = $s + $i } return $s }
class C { method m ($k) { return f2($k) } sub f2 { return main::f($_[0]) } }
print C->new->m(3), "\n";
