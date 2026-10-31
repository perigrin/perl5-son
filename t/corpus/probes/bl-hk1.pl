my %h = (b => 2, c => 3); $h{d} = 4; print join(",", map { "$_=$h{$_}" } sort keys %h), "\n";
