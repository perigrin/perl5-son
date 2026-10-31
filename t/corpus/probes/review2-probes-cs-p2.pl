my @a = (1,2); my $x = 0; my %h;
sub f { my $n = shift; my $m = $n; for my $i (1..$n) { $m = $m + $i; print $i } $h{k} = 1; return $m }
print f(2), "\n";
