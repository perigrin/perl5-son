$_ = "a"; for (1..2) { local $_ = "b"; print } print "$_\n";
