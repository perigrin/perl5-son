our $g = 1;
my @a = (1,2);
sub f { my ($x) = @_; $g = $g + $x; return $g * 2 }
sub h { push @a, 9; return }
my $r = f(3);
h();
my $n = @a;
print "$r $g $n $a[2]\n";
