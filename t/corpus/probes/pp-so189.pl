sub f { my $h = {a=>1}; my $k = join ",", sort keys %$h; $h->{b} = 2; return $k }
print f(), "\n";
