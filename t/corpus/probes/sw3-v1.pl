my %h; for my $p (qw(a:1 b:2 a:3)) { my ($k, $v) = split /:/, $p; push @{ $h{$k} }, $v } print join(";", map { "$_=@{$h{$_}}" } sort keys %h), "\n";
