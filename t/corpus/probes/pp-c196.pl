sub is_x { /x/ } sub show { print $_ }
sub f { my @a = qw(ax b xc); my @g = grep { is_x() } @a; show() for @a; show() for 1 .. 2; return " @g" }
print f(), "\n";
