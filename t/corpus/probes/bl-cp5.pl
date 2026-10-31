use v5.36; sub w ($cb) { $cb->() } my $c = 0; w(sub { $c++ }); print "$c\n";
