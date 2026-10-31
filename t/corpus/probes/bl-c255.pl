my $a = $ARGV[0] // 1;
my $tight = $a && 9;
my $loose = $a and 9;
print "$tight $loose\n";
