package A { sub new { bless {}, $_[0] } sub hi { "a" } } package B { our @ISA = ("A"); sub new { bless {}, $_[0] } } package main; my @o = (A->new, B->new); print join(",", map { $_->hi } @o), "\n";
