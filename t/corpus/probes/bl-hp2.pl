open(my $out, ">", \my $buf); print $out "x"; close($out); my $ok = print $out "y"; print "[$buf][", ($ok ? 1 : 0), "]\n";
