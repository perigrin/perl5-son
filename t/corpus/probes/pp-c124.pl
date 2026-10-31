my %in = (a => [[1, 2], 3], b => [4]); my @dead; push @dead, qw(a b);
my @seen;
for my $d (@dead) {
    for my $i ($in{$d}->@*) {
        if (ref $i) { for my $e ($i->@*) { push @seen, "$d$e" } }
        else { push @seen, "$d$i" }
    }
}
print "@seen\n";
