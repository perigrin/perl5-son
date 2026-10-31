sub f { my %h = (a => 1); my $c = sub { $h{$_[0]} = 1 }; my @k = sort keys %h; $c->("b"); my @l = sort keys %h; %h = (); $c->("c"); return join ",", @k, "|", @l, "|", sort keys %h }
print f(), "\n";
