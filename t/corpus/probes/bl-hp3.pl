my $buf = "s"; open(my $out, ">>", \$buf); my $p = select($out); close($out); print "lost"; select($p); print "[$buf]\n";
