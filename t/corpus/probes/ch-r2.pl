sub id { my ($r) = @_; $r } sub w { my ($x) = @_; id($x) } print ref(w({})), ref(w([])), w(5), "\n";
