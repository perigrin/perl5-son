use v5.38; use experimental 'class';
my $k;
sub f { return defined($k) ? "def" : "undef" }
class C { method m ($k) { return main::f() } }
print C->new->m(2), "\n";
