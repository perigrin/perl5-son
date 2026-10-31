sub f { my ($c, $a, $b) = @_; if ($c) { if ($a && $b) { return } } }
my @r = map { scalar(f(@$_)) // "u" } [1,"P",3],[1,"P",0];
print "@r\n";
