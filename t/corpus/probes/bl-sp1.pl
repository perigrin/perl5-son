sub g { $_[0] = 5 } my %h = (a => 1); my $x = sprintf("%s", $h{a}); g($h{a}); print "$x $h{a}\n";
