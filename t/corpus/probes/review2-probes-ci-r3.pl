sub h { return 4 }
sub g { my $m = shift; return $m * 2 }
print g(3) + h(), "\n";
