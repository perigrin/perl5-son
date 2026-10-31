use v5.42;
sub f ($id, @rest) { return "$id:" . scalar(@rest) }
print f(4), " ", f(1,2,3), "\n";
