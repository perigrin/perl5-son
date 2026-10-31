package O { sub new { bless {}, shift } sub m { $_[1] = 9 } }
sub f { my $o = O->new; my $x = 1; $o->m($x); return $x }
print f(), "\n";
