my @t = ("abc"); sub c { $t[0] = "zzz"; 2 } sub id { "@_" } print id(substr($t[0], 0, 1), c()), "\n";
