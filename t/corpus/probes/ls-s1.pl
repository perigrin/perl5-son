my $e = $ENV{NO_SUCH_VAR} // "ad"; my @c = ("aa" .. $e); print "@c\n";
