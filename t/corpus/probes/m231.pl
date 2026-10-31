use v5.42; use experimental "class";
class K { method isn($x) { $x =~ /a/ }
  method f(@g) { my @r = sort @g; my @n = grep { $self->isn($_) } @r; return "@n" } }
print K->new->f(qw(ba x aa)), "\n";
