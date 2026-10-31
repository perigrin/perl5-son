sub g { return scalar(@_) } my %h = (a => 5); my $n = g(%h); print "$n $h{a}\n";
