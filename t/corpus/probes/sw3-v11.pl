my $str = join "", map { chr(ord($_) + 1) } split //, "abc"; print "$str\n";
