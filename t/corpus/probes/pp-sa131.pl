sub f { my @p = (5); my $c = sub { push @p, $_[0] }; $c->(1); $c->(2); my $a = "@p"; @p = (); $c->(3); return "$a/@p" }
print f(), "\n";
