package C; sub new { bless {}, shift } sub g { "g$_[1]" }
sub f { my ($self, $to, @r) = @_; my $val = '';
  for my $i (0 .. $#r) { my $repr = $r[$i]; $val = $self->g($repr) if $repr ne $to }
  return $val }
package main; print C->new->f('Str', qw(Int Num Str)), "\n";
