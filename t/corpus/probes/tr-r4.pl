sub up { my ($s) = @_; $s =~ tr/a-z/A-Z/; $s } print up("abc"), up("x1"), "\n";
