sub f { my @a; $a[1] = 1; my $s = ""; for my $x (@a) { $a[0] = 5; $s .= $x // "u" } print $s, (exists $a[0] ? "e" : "n"), "\n" }
f();
