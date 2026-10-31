my $n = $ENV{X} // 5;
my $zero = sprintf("%03d", $n);
my $star = sprintf("%*d", $n, $n);
my $left = sprintf("%-*d", $n, $n);
print "[$zero][$star][$left][", $n % 3, "]\n";
