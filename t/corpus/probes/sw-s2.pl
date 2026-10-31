sub f { my %h; for my $x (@_) { next if $x eq "b"; $h{$x}++ } join ",", sort keys %h } print f(qw(a b c a)), "\n";
