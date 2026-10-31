package N { sub new { bless { i => $_[1] }, $_[0] } sub id { $_[0]{i} } } package main; my @o = (N->new(1), N->new(2)); print join(",", map { $_->id } @o), "\n";
