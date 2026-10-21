# A local hash element in a block: stored, then restored at the block's end
sub f { my ($self) = @_; my $r = ""; { local $self->{k} = 5; $r = join ",", sort keys %$self } return "$r / " . join(",", sort keys %$self) }
print f({ a => 1 }), "\n";
