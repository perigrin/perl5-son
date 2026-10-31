sub c { return "z" if $_[0] == 0; return "n" if $_[0] < 0; return "p"; }
print c(0), c(-5), c(7), "\n";
