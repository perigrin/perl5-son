sub load { "loaded " . ($_[0] // "nothing") }
sub find { my ($want) = @_; my $found; if ($want) { $found = "it"; } return load($found) }
print find(1), "; ", find(0), "\n";
