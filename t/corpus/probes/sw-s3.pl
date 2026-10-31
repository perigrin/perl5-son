sub f { my $s = ""; for my $x (@_) { if ($x eq "b") { $s .= "B"; next } elsif ($x eq "c") { last } $s .= $x } $s } print f(qw(a b c d)), "\n";
