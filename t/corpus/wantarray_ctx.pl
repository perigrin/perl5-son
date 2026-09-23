# Wantarray
sub ctx { return wantarray ? "list" : "scalar" }
my @l = ctx();
my $s = ctx();
print "$l[0] $s\n";
