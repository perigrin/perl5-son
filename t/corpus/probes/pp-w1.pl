sub g { $_[0] = 5 }
my $c = 1; g($c); print "$c\n";
my %h = (a => 1); g($h{a}); print "$h{a}\n";
