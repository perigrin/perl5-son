sub f { my ($h, $k) = @_; return $h->{$k} } my %h = (a => 5); print f(\%h, "a"), "\n";
