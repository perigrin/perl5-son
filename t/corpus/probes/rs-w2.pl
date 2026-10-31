sub f { my ($s) = @_; $s =~ s/(\w)(\w)/$2$1/; $s } print f("ab"), f("x"), f("xyz"), "\n";
