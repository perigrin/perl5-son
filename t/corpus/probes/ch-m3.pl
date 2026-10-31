use v5.42; use experimental "class";
class C { field $n = 0; method a { $n = $n + 1; return $self } method b { "b$n" } }
print C->new->a->a->b, "\n";
