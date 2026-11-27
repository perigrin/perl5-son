our $t = "a"; sub c { $t = "zz"; 2 } sub id { "@_" } print id(substr($t, 0), c()), "\n";
