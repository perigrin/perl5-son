# VarDecl in its several shapes
my $scalar = 1;
my @array = (1, 2);
my %hash = (k => 'v');
my ($a, $b) = (10, 20);
our $package_var = 'p';
print "$scalar @array $hash{k} $a $b $package_var\n";
my $late;
$late = 3;
print "$late\n";

# A VarDecl NODE survives only when the initialiser is computed at runtime.
# `my $x = "abc"` folds the constant into the pad slot and emits no VarDecl;
# an expression perl cannot fold keeps the declaration as its own node.
my $computed = "pid:" . $0;
print length($computed) > 0 ? "ok\n" : "no\n";
