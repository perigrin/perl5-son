my %o = (n => 0); for my $x (qw(a b c)) { next if $x eq "b"; $o{n} += 1 } print $o{n}, "\n";
