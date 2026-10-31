sub g { shift @{$_[0]} }
sub f { my $l = [qw(a b c d)]; my $s = ""; for my $x (@$l) { $s .= $x; g($l); $s .= $x . ";" } "$s|@$l" }
print f(), "\n";
