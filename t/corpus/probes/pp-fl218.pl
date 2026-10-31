sub f { my @lines; push @lines, "a", "b"; if ($_[0]) { my @n; for my $l (@lines) { push @n, uc $l } @lines = @n }
  if ($_[1]) { my @n; for my $l (@lines) { push @n, "$l$l" } @lines = @n } my $s = ""; for my $l (@lines) { $s .= $l } return $s }
print f(1, 0), f(0, 1), f(1, 1), f(0, 0), "\n";
