my %m; my @info = (undef, {d => 1}, {d => 2});
sub f { $_[0]{d} == 1 ? 42 : undef }
sub adv { my $id = shift; return $m{$id} if exists $m{$id}; my $i = $info[$id]; return unless defined $i; my $n = f($i); $m{$id} = $n if defined $n; return $n }
my $a = adv(1); my $b = adv(1); my $c = adv(0); my $d = adv(2); my @e = adv(0);
print join(",", map { $_ // 'u' } $a, $b, $c, $d, scalar(@e)), "\n";
