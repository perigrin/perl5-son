# Range -- a LIST-context range with a non-constant bound. A constant range
# (1..4) folds to a const[AV] and emits no Range node, and a `foreach` over a
# range has the op optimised away, so the bound must be a runtime value in a
# list assignment for the node to appear at all.
my $n = 4;
my @q = (1 .. $n);
print scalar(@q), " @q\n";
my $lo = 2;
my @r = ($lo .. $n);
print scalar(@r), " @r\n";
my $empty = 0;
my @e = (1 .. $empty);
print scalar(@e), "\n";
