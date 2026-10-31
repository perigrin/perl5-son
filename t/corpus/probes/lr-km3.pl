package K { sub new { bless { n => $_[1] }, $_[0] } sub n { $_[0]{n} } }
my $k = K->new("x");
my $c = $ARGV[0] // 1;
print(($c && $k->n) ? "t" : "f", "\n");
print $k->n, "\n";
