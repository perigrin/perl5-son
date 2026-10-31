sub c { my $n = shift; if ($n > 5) { return "big" } return "zero" if $n == 0; print "mid\n"; return "small" }
print c(9), c(0), c(3), "\n";
