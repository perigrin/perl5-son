sub ld { "l" . $_[0] } my @a = (1, 2); for (@a) { $_ = $_ + 1; print ld($_) } print " @a\n";
