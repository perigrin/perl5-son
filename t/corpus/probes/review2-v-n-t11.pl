my $c = 0;
sub h { print "h"; return 2 }
sub f { print "a"; my $q = h(); return $q + 1 }
my @l = (5,6,7,8); print $l[f()], "\n";
