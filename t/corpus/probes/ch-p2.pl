package P { sub new { bless { n => 0 }, shift } sub add { my ($self, $x) = @_; $self->{n} += $x; $self } sub n { $_[0]{n} } } my $p = P->new; $p->add(2); print $p->add(3)->n, "\n";
