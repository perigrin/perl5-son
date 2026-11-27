our $t = "a"; sub c { $t = "zz"; 2 } sub id { "$_[0]$_[1]" } print id(substr($t, 0, 1), c()), "\n";
