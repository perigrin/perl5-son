sub a { return } sub b { return undef } sub c { return if $_[0]; return 5 } my @x = (a(), b(), c(1), c(0)); print scalar(@x), "\n";
