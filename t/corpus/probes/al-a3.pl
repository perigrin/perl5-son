sub g { my $w = shift; my $f; if ($w) { $f = "it" } return $f // "no" } print g(1), g(0), "\n";
