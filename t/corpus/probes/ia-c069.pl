sub walk {
    my ($op, $items) = @_;
    my @chain;
    if ($op eq "If" || $op eq "S") {
        push @chain, $op;
        return "stopped at @chain" if $op eq "If";
    }
    for my $item (@$items) { push @chain, $item }
    return "@chain";
}
print walk("If", [1]), " | ", walk("S", [2, 3]), " | ", walk("X", [4]), "\n";
