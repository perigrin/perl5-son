sub f { my ($r, $e) = @_; my $o = ""; for my $s ($e ? @{ $r->{s} // [] } : ()) { $o .= $s } return $o }
print f({s=>[1,2]}, 1), f({}, 1), f({s=>[3]}, 0), "\n";
