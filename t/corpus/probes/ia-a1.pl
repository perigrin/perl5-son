sub f { my ($a) = @_; my $s = "x"; if ($a > 0) { $s .= "p"; return "early $s" if $a > 5 } return "late $s" }
print f(9), "|", f(2), "|", f(-1), "\n";
