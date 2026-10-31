sub f { my @o = (0); for my $x (qw(a b c)) { next if $x eq "b"; $o[0] += 1 } $o[0] } print f(), "\n";
