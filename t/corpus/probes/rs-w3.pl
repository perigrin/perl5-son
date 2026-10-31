sub dbl { $_[0] * 2 } my $s = "n=4"; $s =~ s/(\d)/dbl($1)/e; print "$s\n";
