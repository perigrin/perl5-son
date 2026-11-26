our %g = (a=>1); { local @g{"a"} = (8); } print "$g{a}\n";
