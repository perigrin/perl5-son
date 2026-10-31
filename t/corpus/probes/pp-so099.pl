my %h; $h{a} //= 3; $h{b} ||= 4; $h{b} &&= 5; my @a; $a[1] //= 7; print join(",", map {"$_=$h{$_}"} sort keys %h), " ", scalar(@a), " $a[1]\n";
