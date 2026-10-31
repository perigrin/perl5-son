sub f { my %o = (n => 0); for my $x (@_) { next if $x eq "b"; $o{n} += 1 } $o{n} } print f(qw(a b c)), "\n";
