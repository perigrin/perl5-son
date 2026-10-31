package A { sub new { bless {}, $_[0] } sub hi { "a" } } package C { sub new { bless {}, $_[0] } } package main; my @o = (A->new, C->new); print join(",", map { $_->hi } @o), "\n";
