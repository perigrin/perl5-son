our $t = "a"; sub c { $t = "zz"; 2 } sub id { join ",", @_ } print id(substr($t, 0, 1), c()), "\n";
