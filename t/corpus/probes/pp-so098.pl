sub helpers {
    my ($h, $q) = @_;
    if ($q eq "+") {
        if (!exists $h->{plus}) { $h->{plus} = 1 }
        $h->{seen} = 2;
    }
    return 1;
}
my %h;
helpers(\%h, "+");
print join(",", sort keys %h), "\n";
