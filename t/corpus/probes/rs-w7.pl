my %h = (a => "x"); my $s = "a-b"; $s =~ s/(\w)/$h{$1}/; print "$s\n";
