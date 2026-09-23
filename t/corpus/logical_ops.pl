# And, Or -- the VALUE-returning short circuit, not the control-flow one.
# Binding the result is what keeps the node: in void context perl lowers
# these to a branch and no And/Or reaches the wire.
my $a = 1;
my $b = 0;
my $and = $a && $b;
my $or  = $a || $b;
print "$and $or\n";
my $s = "x";
my $t = $s && "yes";
print "$t\n";
my $u = $b || "default";
print "$u\n";
