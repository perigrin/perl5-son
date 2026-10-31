my $c = [qw(a b c)]; print join("", grep { defined } @{$c}[1, 2]), "\n";
