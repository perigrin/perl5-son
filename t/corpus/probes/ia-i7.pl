sub f { my @o; for my $x (@_) { next if $x eq "b"; push @o, $x } print join(",", @o), "\n" } f(qw(a b c));
