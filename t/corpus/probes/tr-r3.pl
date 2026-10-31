my @w = qw(ab cd); for my $x (@w) { (my $y = $x) =~ tr/a-z/A-Z/; print $y } print "\n";
