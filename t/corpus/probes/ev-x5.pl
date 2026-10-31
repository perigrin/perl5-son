sub g { die "no\n" if $_[0] == 2; "v$_[0]" } my $c = "init"; eval { $c = g(2) }; print "$c\n";
