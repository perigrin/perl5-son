my %h = (a => { v => 5 }); sub f { my ($k, $on) = @_; my $r = "none"; if ($on && (my $x = $h{$k})) { $r = $x->{v} } return $r } print f("a", 1), "\n";
