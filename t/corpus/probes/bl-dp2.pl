package A { sub new { bless {}, $_[0] } sub hi { "a" } sub AUTOLOAD { "auto" } } package main; my @o = (A->new); print join(",", map { $_->hi } @o), "\n";
