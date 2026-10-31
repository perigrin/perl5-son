my @a = qw(x y z); $a[0] = $ENV{G}; my @b = grep { $_ } @a; print "@b\n";
