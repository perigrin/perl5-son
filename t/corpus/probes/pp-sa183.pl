sub mk { my @p; my $c = sub { push @p, $_[0] }; $c->(1); $c->(2); return "@p" }
print mk(), "|", mk(), "\n";
