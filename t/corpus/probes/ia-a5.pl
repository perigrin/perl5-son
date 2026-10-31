sub f { my ($a) = @_; my $s = "x"; if ($a > 0) { return "early" if $a > 5 } for my $i (1 .. 2) { $s .= $i } return "late $s" }
print f(9), "|", f(2), "\n";
