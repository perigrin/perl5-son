my %h = (a => 1, b => 2); for my $k (sort keys %h) { next if $k eq "a"; $h{$k} *= 10 } print "$h{a} $h{b}\n";
