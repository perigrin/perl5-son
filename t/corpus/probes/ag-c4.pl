sub f { return $_[0] . "-" . $_[1] . "-" . scalar(@_) } print f("a", "b"), "\n";
