my %h = (a => 1); my $k = "zz"; $k = $k . ""; print defined($h{$k}) ? "d" : "u", "\n";
