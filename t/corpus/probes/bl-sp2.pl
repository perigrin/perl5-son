sub g { $_[0] = 5 } my %h = (a => 1); my $c = 1; my $x = "" . ($c ? $h{a} : 8); g($h{a}); print "$x $h{a}\n";
