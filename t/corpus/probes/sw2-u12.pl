my %h = (a => 1); delete $h{a}; print exists $h{a} ? "y" : "n", scalar(keys %h), "\n";
