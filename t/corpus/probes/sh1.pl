sub g { "<$_[0]>" }
sub f { my @w = (1, 2); my $s = ""; while (my $n = shift @w) { $s .= g($n) } $s }
print f(), "\n";
