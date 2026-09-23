# Repeat, AnonSub, Assign, VarDecl, PadAccess
my $line = "-" x 10;
print "$line\n";
my @three = (0) x 3;
print scalar(@three), "\n";
my $code = sub { my ($a, $b) = @_; return $a + $b };
print $code->(2, 3), "\n";
my $acc = 0;
$acc = $acc + 7;
print "$acc\n";
