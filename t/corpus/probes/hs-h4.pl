my %h = (a => 1); $h{a} = undef; print exists $h{a} ? "e" : "n", defined $h{a} ? "d" : "u", "\n";
