my %h = (a => 1); my $r = \%h; $r->{a} = 7; $r->{q} = 8; print "$h{a} $h{q}\n";
