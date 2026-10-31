sub add { my ($h) = @_; $h->{b} = 2; 2 }
sub f { my %pre = (a => 1); my $s = join(",", sort keys %pre); add(\%pre); return "$s|" . join(",", sort keys %pre) }
print f(), "\n";
