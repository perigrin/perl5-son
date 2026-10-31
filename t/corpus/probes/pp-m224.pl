package C; sub new { bless { cache => {}, bind => undef }, shift }
sub inner { my ($self) = @_; join ",", sort keys(($self->{bind} // {})->%*) }
sub f { my ($self, @args) = @_;
  unless (@args) { my $r = $self->inner; $self->{cache}{n} = $r; return $r }
  local $self->{bind} = { ($self->{bind} // {})->%* };
  $self->{bind}{$_} = 1 for @args;
  my $r = $self->inner; $self->{cache}{n} = $r; return $r }
package main; my $o = C->new; print $o->f(), "|", $o->f(qw(a b)), "|", $o->inner, "\n";
