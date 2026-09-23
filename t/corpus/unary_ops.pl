# Length, Not, Xor, Defined -- each in a context perl does NOT fold away.
# A constant operand gets folded, so every subject here is a live variable.
my $s = "abc";
my $e = "";
print length($s), "\n";
print length($e), "\n";
print((!$s) ? 1 : 0, "\n");
print((!$e) ? 1 : 0, "\n");
print defined($s) ? 1 : 0, "\n";
my $u;
print defined($u) ? 1 : 0, "\n";
my $p = 1;
my $q = 0;
print(($p xor $q) ? 1 : 0, "\n");
print(($p xor $p) ? 1 : 0, "\n");
