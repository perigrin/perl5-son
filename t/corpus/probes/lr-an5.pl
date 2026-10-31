sub f { my ($c, $a, $b) = @_; if ($a && $b) { return 1 } return 2 }
my @r = map { f(@$_) } [1,"P",3],[1,"P",0];
print "@r\n";
