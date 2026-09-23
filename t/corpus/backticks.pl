# BacktickExpr -- a command whose output is captured
my $out = `echo fixture`;
print $out;
my @lines = `printf 'a\nb\n'`;
print scalar(@lines), "\n";
