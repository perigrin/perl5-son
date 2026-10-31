my $first = shift // 7;
my $g = 5;
sub f { my $n = shift; print "$n $g\n"; return 0 }
f(1);
print "$first\n";
