sub last_is_for   { my @seen; for my $x (@_) { push @seen, $x * 2 } }
sub last_is_while { my $i = 0; while ($i < 2) { $i++ } }
my @f = last_is_for(1, 2);
my @w = last_is_while();
my $s = last_is_for(3);
print scalar(@f), scalar(@w), "[", $f[0], "][", $s, "]\n";
