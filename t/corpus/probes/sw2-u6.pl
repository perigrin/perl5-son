sub mk { my $n = shift; return sub { return $n * $_[0] } } my $d = mk(2); print $d->(5), "\n";
