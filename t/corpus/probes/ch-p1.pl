package P { sub new { bless { n => 0 }, shift } sub add { my $self = shift; $self->{n} += $_[0]; return $self } sub n { $_[0]{n} } } print P->new->add(2)->add(3)->n, "\n";
