my %h = (a => 1); my $r = \%h; sub f { my $x = shift; $x->{a} = 7; return 0 } f($r); print "$h{a}\n";
