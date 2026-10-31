sub g { return $_[0] * 2 }
sub f { return g($_[0] + 1) }
my $r = f(3); print $r + 1, "\n";
