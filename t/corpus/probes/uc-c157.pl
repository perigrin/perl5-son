use v5.42; no warnings;
sub f ($d) { my $x = 0; try { $x = 1; die "no\n" if $d; $x = 3 } catch ($e) { print "c" } return $x }
print f(0), f(1), "\n";
