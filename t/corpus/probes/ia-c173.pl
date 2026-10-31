use v5.42; no warnings;
sub g { die "no\n" if $_[0] == 3; return $_[0] * 2 }
sub f { my @out; for my $s (@_) { my $c; try { $c = g($s) } catch ($e) { return "R@out" } push @out, $c } return "@out" }
print f(1, 2, 3, 4), " ", f(1, 2), "\n";
