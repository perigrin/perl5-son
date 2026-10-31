sub inc { my ($h, $k) = @_; $h->{$k} = ($h->{$k} // 0) + 1 } my %c; inc(\%c, "x"); inc(\%c, "x"); inc(\%c, "y"); print "$c{x}$c{y}\n";
