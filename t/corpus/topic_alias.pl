# A callee reads and writes the foreach topic by name: aliased each pass
sub is_x { /x/ } sub bump { $_ .= "!" }
sub f { my @a = qw(ax b xc); bump() for @a; my @g = grep { is_x() } @a; return "@g|@a" }
print f(), "\n";
