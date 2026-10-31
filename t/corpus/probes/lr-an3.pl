my %t;
sub f { my ($c, $a, $b) = @_; if ($c) { if ($a && $b) { $t{$b} = $a; return } } }
my @r = map { scalar(f(@$_)) // "u" } [1,"P",3],[1,"P",0];
print "@r|", join(",", map {"$_=$t{$_}"} sort keys %t), "\n";
