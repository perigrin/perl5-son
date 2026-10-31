my @l = ($ENV{A} // "a", "b");
sub pair { return $l[0], $l[1]; }
sub group { return ($l[0], $l[1]); }
sub one { return $l[0]; }
my @p = pair();
my @g = group();
print scalar(@p), scalar(@g), one(), "\n";
print "@p|@g\n";
