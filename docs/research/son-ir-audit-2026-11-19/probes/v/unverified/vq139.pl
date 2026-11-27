my $t = "abc"; sub id { "@_" } print id(pos($t), $t = "z"), "\n";
