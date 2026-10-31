my @a = (1); my %h = (k => 1); my $n = 5; my $ar = \@a; my $hr = \%h; my $sr = \$n; print ref($ar), " ", ref($hr), " ", ref($sr), " ", ${$sr}, "\n";
