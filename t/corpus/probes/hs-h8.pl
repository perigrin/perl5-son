my %h = (a => 1); my $n = 1; $n = $n + 0; if ($n) { $h{b} = 5 } print $h{b} // "u", "\n";
