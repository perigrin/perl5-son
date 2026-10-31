use v5.36; sub app ($cb, $v) { $cb->($v) } sub twice ($cb) { app($cb, 3) + app($cb, 4) } my $m = 2; print twice(sub ($x) { $x * $m }), "\n";
