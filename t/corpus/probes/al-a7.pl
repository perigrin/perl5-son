sub ld { "l" . ($_[0] // "n") } my $w = 1; $w = $w + 0; my $f; if ($w) { $f = "it" } print ld($f), "\n";
