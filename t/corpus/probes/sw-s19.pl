sub f { my %h = (a => 1); for my $x (@_) { next if exists $h{$x}; $h{$x} = 2 } join ",", map { "$_$h{$_}" } sort keys %h } print f(qw(a b)), "\n";
