my %h; for my $x (qw(a b a)) { if (exists $h{$x}) { $h{$x} .= "!"; next } $h{$x} = $x } print join(",", map { $h{$_} } sort keys %h), "\n";
