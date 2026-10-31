my $n = 0;
sub fresh { $n++; "%t$n" }
sub go { my ($a, $b, $c) = (fresh(), fresh(), fresh()); print "  $a = x\n"; print "  $b = $a\n"; return $c }
print go(), "\n";
