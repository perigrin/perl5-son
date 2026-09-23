# HashLiteral, Exists, Delete, Slice, Length, Count, PostfixDeref, Ref, RefType
my %h = (a => 1, b => 2, c => 3);
print exists $h{a} ? "y" : "n", "\n";
delete $h{a};
print join(",", sort keys %h), "\n";
my @slice = @h{qw(b c)};
print "@slice\n";
my @arr = (1, 2, 3, 4);
print scalar(@arr), "\n";
print length("hello"), "\n";
my $r = \@arr;
print ref($r), "\n";
print scalar($r->@*), "\n";
print "$$r[0]\n";
