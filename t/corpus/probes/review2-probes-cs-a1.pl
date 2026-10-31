my $c = 0; sub inc { if ($c >= 0) { $c = $c + 1 } return 0 } inc(); inc(); print "$c\n";
