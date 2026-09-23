# MakeCell, CellRead, CellWrite, CellParam -- a closed-over variable
sub make_counter {
    my $count = shift;
    return sub { $count++; return $count };
}
my $c = make_counter(10);
print $c->(), "\n";
print $c->(), "\n";
my $d = make_counter(100);
print $d->(), "\n";
