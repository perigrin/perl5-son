for my $x (qw(a b c)) { my @o = (0); next if $x eq "b"; $o[0] += 1; print $o[0] } print "\n";
