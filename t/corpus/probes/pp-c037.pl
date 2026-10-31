sub id { $_[0] }
sub keep {
    my $out = "";
    for my $x (@_) {
        next unless id($x) > 1;
        $out .= $x;
    }
    return $out;
}
print keep(1, 2, 3), "\n";
