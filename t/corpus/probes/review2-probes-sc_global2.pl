$main::c = 3; sub inc { my $n = shift; if ($n) { $main::c = $n } return 0 } inc(7); print "$main::c\n";
