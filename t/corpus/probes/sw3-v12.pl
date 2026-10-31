my %h = map { $_ => length $_ } qw(aa b ccc); print join(",", map { "$_$h{$_}" } sort keys %h), "\n";
