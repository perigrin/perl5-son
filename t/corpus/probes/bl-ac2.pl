sub f { my @x = @_; return @x ? "some" : "none" } print f(1), f(), "\n";
