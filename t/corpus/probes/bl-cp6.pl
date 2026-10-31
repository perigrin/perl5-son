sub app { $_[0]->($_[1]) } sub twice { app($_[0], 3) + app($_[0], 4) } my $m = 2; print twice(sub { $_[0] * $m }), "\n";
