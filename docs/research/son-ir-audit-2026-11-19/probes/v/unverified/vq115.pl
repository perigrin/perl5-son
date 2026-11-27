our $t = "a"; sub c { $t = "zz"; 2 } sub id { my ($p, $q) = @_; "$p$q" } print id(substr($t, 0, 1), c()), "\n";
