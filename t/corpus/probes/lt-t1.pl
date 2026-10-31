my @a = (1, 2); my @b = (3); my $c = @ARGV ? 0 : 1;
my @r = $c ? @a : @b; print "@r\n";
for my $e ($c ? @a : ()) { print $e } print "\n";
print join(",", $c ? @b : @a), "\n";
