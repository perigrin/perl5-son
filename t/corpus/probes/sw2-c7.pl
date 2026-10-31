sub g { my $t = 0; my $f = sub { $t += $_[0] }; $f->(3); $f->(4); return $t } print g(), "\n";
