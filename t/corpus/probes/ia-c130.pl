sub f { my @pending; my $commit = sub { push @pending, $_[0] }; my $out = "";
  for my $pos (1 .. 3) { $commit->($pos); $commit->($pos * 10) if $pos == 2;
    if (@pending) { for my $s (@pending) { for my $k (1 .. 2) { $out .= length($s) } $out .= $s } @pending = () } $out .= "|" }
  return $out }
print f(), "\n";
