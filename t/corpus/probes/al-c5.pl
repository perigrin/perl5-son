sub ld { "l" . ($_[0] // "n") } sub find { my $want = shift; my $found; if ($want) { $found = "it"; } return ld($found) } print find(1), ";", find(0), "\n";
