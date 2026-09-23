# Unwind (a die leaving the frame), and the eval that catches it
my $r = eval { die "boom\n"; 1 };
print defined($r) ? "defined" : "undef", "\n";
print $@;
sub thrower { die "inner\n" }
eval { thrower() };
print $@;
