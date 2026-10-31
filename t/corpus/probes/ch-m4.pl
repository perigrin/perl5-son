use v5.42; use experimental "class";
class C { field $n = 0; method a ($x) { return undef if $x; return $self } method b { "b" } }
my $r = C->new->a(0); print $r->b, "\n";
