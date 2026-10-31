my %h; for my $w (qw(a b a c b a)) { $h{$w}++ } print join(",", map { "$_=$h{$_}" } sort keys %h), "\n";
