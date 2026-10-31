my %cache = (hb => "cached");
sub make {
    my ($op) = @_;
    if ($op eq "P") { return "phi" }
    my $key = $op or die "no op\n";
    return $cache{"h$key"} if exists $cache{"h$key"};
    return "new $key";
}
print make("P"), " ", make("a"), " ", make("b"), "\n";
