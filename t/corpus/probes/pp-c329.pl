my ($x, $y, %h);
my $p = $x++;
my $q = $y--;
my $r = $h{k}++;
my $s = "aa";
my $t = $s++;
print join(",", map { defined $_ ? "[$_]" : "undef" } $p, $q, $r, $t), "\n";
