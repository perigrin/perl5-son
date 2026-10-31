use v5.42; use experimental "class";
class C { method a { return $self } method b { "b" } }
my $c = C->new; my $d = $c->a; print $d->b, "\n";
