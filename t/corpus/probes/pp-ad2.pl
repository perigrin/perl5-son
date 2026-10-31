my %h = (k => "s"); my @a = (1, 2); $a[1] = $h{k}; $a[0] = $h{z}; print defined $a[0] ? "d" : "u", "\n";
