sub f { my $n = shift; return defined($n) ? "def" : "undef" } my @a = (1); print f($a[3]), f($a[0]), "\n";
