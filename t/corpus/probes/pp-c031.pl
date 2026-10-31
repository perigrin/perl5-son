sub bump_alias {
    $_[0]++;
}
sub bump_copy {
    my ($n) = @_;
    $n++;
}
my ($aliased, $untouched) = (1, 1);
bump_alias($aliased);
bump_copy($untouched);
print "$aliased $untouched\n";
