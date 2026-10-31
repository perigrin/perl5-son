sub f { my $n = shift; if (defined $n) { print "def\n" } else { print "undef\n" } return 0 } my @a = (1); f($a[3]); f($a[0]);
