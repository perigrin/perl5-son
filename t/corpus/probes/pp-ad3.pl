sub f { defined $_[0] ? "d" : "u" } my %h = (k => "s"); my $v = $h{z}; my $w = $h{k}; print f($v), f($w), "\n"; our $p = $h{z}; print defined $p ? "d" : "u", "\n";
