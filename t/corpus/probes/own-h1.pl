sub add { $_[0]{a} = "x" } my %h = (a => 1); add(\%h); print "$h{a}\n";
